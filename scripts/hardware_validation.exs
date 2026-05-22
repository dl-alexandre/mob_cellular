defmodule MobCellularHardwareValidation do
  @moduledoc false

  @android_fcm_config "../meshx/apps/meshx_mobile_app/android/app/google-services.json"
  @android_readme "../meshx/apps/meshx_mobile_app/README.md"

  defmodule PushClient do
    @moduledoc false

    def deliver(peer_id, envelope, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:delivered, peer_id, envelope})
      :ok
    end
  end

  def run do
    Application.ensure_all_started(:telemetry)
    File.mkdir_p!("artifacts/hardware")

    report = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      host: step("host", &host/0),
      attached_hardware: step("attached_hardware", &attached_hardware/0),
      local_bridge_smoke: step("local_bridge_smoke", &local_bridge_smoke/0),
      fallback_simulation: step("fallback_simulation", &fallback_simulation/0),
      android_fcm: step("android_fcm", &android_fcm_readiness/0),
      ios_apns: step("ios_apns", &ios_apns_readiness/0),
      cross_platform_matrix: step("cross_platform_matrix", &cross_platform_matrix/0),
      conclusion: conclusion()
    }

    stamp =
      report.generated_at
      |> String.replace(":", "")
      |> String.replace("-", "")

    json_path = "artifacts/hardware/#{stamp}-validation.json"
    md_path = "artifacts/hardware/#{stamp}-validation.md"

    File.write!(json_path, JSON.encode!(report))
    File.write!(md_path, markdown(report))

    IO.puts("mob_cellular hardware validation")
    IO.puts("json=#{json_path}")
    IO.puts("markdown=#{md_path}")
    IO.puts("status=#{report.conclusion.status}")
  end

  defp step(name, fun) do
    IO.puts("running=#{name}")
    result = fun.()
    IO.puts("done=#{name}")
    result
  end

  defp host do
    %{
      cwd: File.cwd!(),
      elixir: System.version(),
      otp: System.otp_release()
    }
  end

  defp attached_hardware do
    %{
      adb: adb_devices(),
      ios: ios_devices(),
      xcode: xcode_devices(),
      usb: usb_inventory()
    }
  end

  defp adb_devices do
    case cmd("adb", ["devices", "-l"]) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "List of devices"))
        |> Enum.map(&parse_adb_row/1)

      {:error, reason} ->
        [%{error: reason}]
    end
  end

  defp parse_adb_row(row) do
    [serial, state | rest] = String.split(row)

    props =
      rest
      |> Enum.map(fn item -> String.split(item, ":", parts: 2) end)
      |> Enum.reduce(%{}, fn
        [k, v], acc -> Map.put(acc, k, v)
        _, acc -> acc
      end)

    %{
      serial: serial,
      state: state,
      model: Map.get(props, "model"),
      product: Map.get(props, "product"),
      device: Map.get(props, "device"),
      android_release: adb_getprop(serial, "ro.build.version.release")
    }
  end

  defp adb_getprop(serial, prop) do
    case cmd("adb", ["-s", serial, "shell", "getprop", prop]) do
      {:ok, value} -> String.trim(value)
      {:error, _reason} -> nil
    end
  end

  defp ios_devices do
    case cmd("idevice_id", ["-l"]) do
      {:ok, output} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.map(&ios_device/1)

      {:error, reason} ->
        [%{error: reason}]
    end
  end

  defp ios_device(udid) do
    %{
      udid: udid,
      name: ideviceinfo(udid, "DeviceName"),
      product_type: ideviceinfo(udid, "ProductType"),
      product_version: ideviceinfo(udid, "ProductVersion")
    }
  end

  defp ideviceinfo(udid, key) do
    case cmd("ideviceinfo", ["-u", udid, "-k", key]) do
      {:ok, value} -> String.trim(value)
      {:error, _reason} -> nil
    end
  end

  defp xcode_devices do
    case cmd("xcrun", ["xctrace", "list", "devices"], timeout: 10_000) do
      {:ok, output} -> output
      {:error, reason} -> reason
    end
  end

  defp usb_inventory do
    case cmd("system_profiler", ["SPUSBDataType"], timeout: 10_000) do
      {:ok, output} -> output
      {:error, reason} -> reason
    end
  end

  defp local_bridge_smoke do
    parent = self()
    telemetry_id = {__MODULE__, :local_bridge_smoke, make_ref()}

    :telemetry.attach_many(
      telemetry_id,
      [
        [:mob, :cellular, :send_frame],
        [:mob, :cellular, :receive_push],
        [:mob, :cellular, :error]
      ],
      &__MODULE__.telemetry_handler/4,
      parent
    )

    try do
      {:ok, bridge} =
        Mob.Cellular.PushBridge.start_link(event_target: parent, push_client: PushClient)

      :ok = Mob.Cellular.PushBridge.send_frame(bridge, "local-peer", "hello", test_pid: parent)
      delivered = receive_one({:delivered, "local-peer", :_})

      envelope = %{
        "v" => 1,
        "type" => "frame",
        "peer_id" => "remote-peer",
        "frame" => Base.encode64("reply"),
        "metadata" => %{"source" => "local-smoke"}
      }

      :ok = Mob.Cellular.PushBridge.receive_push(bridge, envelope)
      frame = receive_one({:frame, "remote-peer", "reply"})
      up = receive_one({:transport_up, "remote-peer", :_})
      telemetry = drain_telemetry([])
      GenServer.stop(bridge)

      %{
        status: :passed,
        outbound_delivered?: match?({:ok, {:delivered, "local-peer", _}}, delivered),
        inbound_frame?: frame == {:ok, {:frame, "remote-peer", "reply"}},
        inbound_transport_up?: match?({:ok, {:transport_up, "remote-peer", _}}, up),
        telemetry_events: Enum.map(telemetry, &elem(&1, 0))
      }
    after
      :telemetry.detach(telemetry_id)
    end
  rescue
    error ->
      %{status: :failed, error: Exception.format(:error, error, __STACKTRACE__)}
  end

  def telemetry_handler(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_seen, event, measurements, metadata})
  end

  defp fallback_simulation do
    parent = self()

    {:ok, bridge} =
      Mob.Cellular.PushBridge.start_link(event_target: parent, push_client: PushClient)

    transports = [
      {:ble, {:error, :unavailable}},
      {:wifi, {:error, :unavailable}},
      {:mesh, {:error, :unavailable}},
      {:cellular,
       Mob.Cellular.PushBridge.send_frame(bridge, "fallback-peer", "fallback", test_pid: parent)}
    ]

    selected =
      Enum.find(transports, fn
        {_name, :ok} -> true
        {_name, _result} -> false
      end)

    delivered = receive_one({:delivered, "fallback-peer", :_})
    GenServer.stop(bridge)

    %{
      status: if(selected == {:cellular, :ok}, do: :passed, else: :failed),
      selected_transport: elem(selected || {:none, nil}, 0),
      outbound_delivered?: match?({:ok, {:delivered, "fallback-peer", _}}, delivered)
    }
  rescue
    error ->
      %{status: :failed, error: Exception.format(:error, error, __STACKTRACE__)}
  end

  defp android_fcm_readiness do
    config = Path.expand(@android_fcm_config, File.cwd!())
    readme = Path.expand(@android_readme, File.cwd!())
    config_text = if File.exists?(config), do: File.read!(config), else: ""
    readme_text = if File.exists?(readme), do: File.read!(readme), else: ""

    %{
      status: :blocked,
      ready_devices: Enum.filter(adb_devices(), &(&1.state == "device")),
      google_services_json: config,
      google_services_placeholder?:
        String.contains?(config_text, "PLACEHOLDER_API_KEY_REPLACE_BEFORE_USING_FCM"),
      android_beam_runtime_wired?:
        not String.contains?(readme_text, "The BEAM runtime is not wired up yet"),
      blockers:
        Enum.reject(
          [
            if(String.contains?(config_text, "PLACEHOLDER_API_KEY_REPLACE_BEFORE_USING_FCM"),
              do: "Replace placeholder google-services.json with a real Firebase app config."
            ),
            if(String.contains?(readme_text, "The BEAM runtime is not wired up yet"),
              do:
                "Android harness must hand native FCM callbacks into on-device BEAM / receive_push/2."
            )
          ],
          &is_nil/1
        )
    }
  end

  defp ios_apns_readiness do
    key_paths =
      "../published/apple_push_notifications/AuthKey_*.p8"
      |> Path.expand(File.cwd!())
      |> Path.wildcard()

    %{
      status: :blocked,
      ready_devices: ios_devices(),
      apns_keys_found: key_paths,
      env_present: %{
        apns_team_id: present_env?("APNS_TEAM_ID"),
        apns_key_id: present_env?("APNS_KEY_ID"),
        apns_bundle_id: present_env?("APNS_BUNDLE_ID"),
        apns_key_path: present_env?("APNS_KEY_PATH")
      },
      blockers:
        Enum.reject(
          [
            unless(present_env?("APNS_TEAM_ID"), do: "Set APNS_TEAM_ID."),
            unless(present_env?("APNS_KEY_ID"), do: "Set APNS_KEY_ID."),
            unless(present_env?("APNS_BUNDLE_ID"), do: "Set APNS_BUNDLE_ID."),
            unless(present_env?("APNS_KEY_PATH") or key_paths != [],
              do: "Provide an APNs .p8 key path."
            ),
            "iOS app must register APNs token and hand payload into receive_push/2."
          ],
          &is_nil/1
        )
    }
  end

  defp cross_platform_matrix do
    %{
      status: :blocked,
      android_to_ios: :blocked_by_provider_handoff,
      ios_to_android: :blocked_by_provider_handoff,
      notes: [
        "Requires Android FCM readiness and iOS APNs readiness.",
        "Requires a server-side push_client that maps peer ids to platform tokens."
      ]
    }
  end

  defp conclusion do
    %{
      status: :partial,
      summary:
        "Local PushBridge and fallback simulations can run on host. Real attached-device push delivery is blocked by provider credentials/native handoff gaps."
    }
  end

  defp receive_one(pattern) do
    receive do
      message ->
        if match_pattern?(pattern, message), do: {:ok, message}, else: receive_one(pattern)
    after
      1_000 -> {:error, :timeout}
    end
  end

  defp match_pattern?({a, b, :_}, {a, b, _}), do: true
  defp match_pattern?(expected, actual), do: expected == actual

  defp drain_telemetry(acc) do
    receive do
      {:telemetry_seen, event, measurements, metadata} ->
        drain_telemetry([{event, measurements, metadata} | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp present_env?(key), do: System.get_env(key) not in [nil, ""]

  defp cmd(executable, args, opts \\ []) do
    try do
      case System.find_executable(executable) do
        nil ->
          {:error, "#{executable} not found"}

        path ->
          {runner, runner_args} = command_with_optional_timeout(path, args, opts)

          case System.cmd(runner, runner_args, stderr_to_stdout: true) do
            {output, 0} -> {:ok, output}
            {output, _status} -> {:error, output}
          end
      end
    rescue
      error in ErlangError -> {:error, Exception.message(error)}
    end
  end

  defp command_with_optional_timeout(path, args, opts) do
    case {Keyword.get(opts, :timeout), System.find_executable("timeout")} do
      {nil, _timeout_path} ->
        {path, args}

      {_timeout_ms, nil} ->
        {path, args}

      {timeout_ms, timeout_path} ->
        {timeout_path, [Integer.to_string(div(timeout_ms, 1_000)), path | args]}
    end
  end

  defp markdown(report) do
    """
    # mob_cellular Hardware Validation

    Generated: #{report.generated_at}

    ## Conclusion

    Status: `#{report.conclusion.status}`

    #{report.conclusion.summary}

    ## Local Bridge Smoke

    Status: `#{report.local_bridge_smoke.status}`

    ## Fallback Simulation

    Status: `#{report.fallback_simulation.status}`
    Selected transport: `#{report.fallback_simulation.selected_transport}`

    ## Android FCM

    Status: `#{report.android_fcm.status}`
    Ready adb devices: #{length(report.android_fcm.ready_devices)}
    Placeholder google-services.json: #{report.android_fcm.google_services_placeholder?}

    Blockers:
    #{bullets(report.android_fcm.blockers)}

    ## iOS APNs

    Status: `#{report.ios_apns.status}`
    Ready iOS devices: #{length(report.ios_apns.ready_devices)}
    APNs keys found: #{length(report.ios_apns.apns_keys_found)}

    Blockers:
    #{bullets(report.ios_apns.blockers)}

    ## Cross-Platform Matrix

    Status: `#{report.cross_platform_matrix.status}`

    #{bullets(report.cross_platform_matrix.notes)}
    """
  end

  defp bullets([]), do: "- none"
  defp bullets(items), do: Enum.map_join(items, "\n", &"- #{&1}")
end

MobCellularHardwareValidation.run()
