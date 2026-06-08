defmodule Mob.Cellular.PushBridgeTest do
  use ExUnit.Case, async: true

  alias Mob.Cellular.CarrierRejectedError
  alias Mob.Cellular.PushBridge
  import ExUnit.CaptureLog

  defmodule PushClient do
    @moduledoc false

    def deliver(peer_id, envelope, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:push_delivered, peer_id, envelope})
      :ok
    end
  end

  defmodule SelectivePushClient do
    @moduledoc false

    def deliver("bad", _envelope, _opts), do: {:error, :provider_rejected}
    def deliver(peer_id, envelope, opts), do: PushClient.deliver(peer_id, envelope, opts)
  end

  defmodule RaisingPushClient do
    @moduledoc false

    def deliver(_peer_id, _envelope, _opts), do: raise("provider unavailable")
  end

  def handle_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  setup do
    telemetry_id = {__MODULE__, self()}

    :telemetry.attach_many(
      telemetry_id,
      [
        [:mob, :cellular, :send_frame],
        [:mob, :cellular, :receive_push],
        [:mob, :cellular, :error]
      ],
      &__MODULE__.handle_telemetry/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(telemetry_id) end)

    :ok
  end

  describe "start_link/1" do
    test "requires event_target" do
      assert {:error, {:missing_required_option, :event_target}} = PushBridge.start_link([])
    end

    test "rejects sms because the initial bridge is push-only" do
      assert_raise CarrierRejectedError, fn ->
        PushBridge.start_link(event_target: self(), carrier: :sms)
      end
    end
  end

  describe "Mob.Transport behaviour" do
    test "delivers frames through an injected push client" do
      {:ok, bridge} = PushBridge.start_link(event_target: self(), push_client: PushClient)

      assert :ok = PushBridge.send_frame(bridge, "peer-1", "hello", test_pid: self())

      assert_receive {:push_delivered, "peer-1",
                      %{"type" => "frame", "peer_id" => "peer-1", "frame" => encoded}}

      assert {:ok, "hello"} = Base.decode64(encoded)

      assert_receive {:telemetry, [:mob, :cellular, :send_frame], measurements,
                      %{peer_id: "peer-1", result: :ok}}

      assert measurements.payload_size > 0
      assert is_integer(measurements.duration)

      GenServer.stop(bridge)
    end

    test "returns an error when no push client is configured" do
      {:ok, bridge} = PushBridge.start_link(event_target: self())

      assert {:error, :push_client_not_configured} =
               PushBridge.send_frame(bridge, "peer-1", "hello")

      assert_receive {:telemetry, [:mob, :cellular, :error], %{},
                      %{
                        operation: :send_frame,
                        peer_id: "peer-1",
                        reason: {:error, :push_client_not_configured}
                      }}

      GenServer.stop(bridge)
    end

    test "returns a structured error when push client raises" do
      {:ok, bridge} = PushBridge.start_link(event_target: self(), push_client: RaisingPushClient)

      assert capture_log(fn ->
               assert {:error, {:push_client_exception, RuntimeError}} =
                        PushBridge.send_frame(bridge, "peer-1", "hello")
             end) =~ "mob_cellular push delivery failed"

      GenServer.stop(bridge)
    end

    test "broadcast requires explicit recipients" do
      {:ok, bridge} = PushBridge.start_link(event_target: self(), push_client: PushClient)

      assert {:error, :recipients_required} = PushBridge.broadcast_frame(bridge, "hello")

      assert {:ok, %{"a" => :ok, "b" => :ok}} =
               PushBridge.broadcast_frame(bridge, "hello",
                 recipients: ["a", "b"],
                 test_pid: self()
               )

      assert_receive {:push_delivered, "a", _}
      assert_receive {:push_delivered, "b", _}

      GenServer.stop(bridge)
    end

    test "broadcast reports per-recipient errors" do
      {:ok, bridge} =
        PushBridge.start_link(event_target: self(), push_client: SelectivePushClient)

      assert {:ok, %{"a" => :ok, "bad" => {:error, :provider_rejected}}} =
               PushBridge.broadcast_frame(bridge, "hello",
                 recipients: ["a", "bad"],
                 test_pid: self(),
                 max_concurrency: 2
               )

      GenServer.stop(bridge)
    end

    test "rejects payloads over the configured JSON byte budget" do
      {:ok, bridge} =
        PushBridge.start_link(
          event_target: self(),
          push_client: PushClient,
          max_payload_bytes: 10
        )

      assert {:error, {:payload_too_large, actual, 10}} =
               PushBridge.send_frame(bridge, "peer-1", "hello")

      assert actual > 10
      GenServer.stop(bridge)
    end
  end

  describe "envelope helpers" do
    test "serialized_size/1 measures JSON bytes" do
      envelope = %{"v" => 1, "type" => "peer_up", "peer_id" => "peer-1"}

      assert {:ok, bytes} = PushBridge.serialized_size(envelope)
      assert bytes == byte_size(JSON.encode!(envelope))
    end
  end

  describe "inbound push envelopes" do
    test "emits canonical frame and reachability events" do
      {:ok, bridge} = PushBridge.start_link(event_target: self())

      envelope = %{
        "v" => 1,
        "type" => "frame",
        "peer_id" => "peer-1",
        "frame" => Base.encode64("hello"),
        "metadata" => %{"provider" => "fcm"}
      }

      assert :ok = PushBridge.receive_push(bridge, envelope)
      assert_receive {:frame, "peer-1", "hello"}
      assert_receive {:transport_up, "peer-1", %{"provider" => "fcm"}}
      assert_receive {:telemetry, [:mob, :cellular, :receive_push], measurements, %{result: :ok}}
      assert measurements.payload_size > 0

      GenServer.stop(bridge)
    end

    test "emits transport_error for malformed payloads" do
      {:ok, bridge} = PushBridge.start_link(event_target: self())

      assert {:error, {:missing_required_key, :frame}} =
               PushBridge.receive_push(bridge, %{
                 "v" => 1,
                 "type" => "frame",
                 "peer_id" => "peer-1"
               })

      assert_receive {:transport_error, {:missing_required_key, :frame}}

      assert_receive {:telemetry, [:mob, :cellular, :error], %{},
                      %{operation: :receive_push, reason: {:missing_required_key, :frame}}}

      GenServer.stop(bridge)
    end
  end
end
