defmodule Mob.Cellular.PushBridge do
  @moduledoc """
  Push-notification implementation of the `Mob.Transport` behaviour.

  The bridge owns the normalized cellular transport process. It does not embed
  Firebase or APNs credentials; outbound delivery is delegated to an injected
  `:push_client` module that implements `deliver/3`.

  Incoming push payloads can be delivered to the bridge with
  `receive_push/2`. Decoded frame envelopes are emitted to `:event_target` as
  canonical `Mob.Transport` events.
  """

  use GenServer

  if Code.ensure_loaded?(Mob.Transport) do
    @behaviour Mob.Transport
  end

  require Logger

  @envelope_version 1
  @default_payload_budget 3_500

  @type push_client :: module()
  @type state :: %{
          event_target: pid(),
          config: keyword() | map(),
          push_client: push_client() | nil,
          max_payload_bytes: pos_integer()
        }

  def start_link(opts) do
    with :ok <- require_event_target(opts),
         :ok <- validate_start_config(opts) do
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Injects an inbound push payload into the bridge.

  Payloads may use atom or string keys:

      %{"v" => 1, "type" => "frame", "peer_id" => "peer", "frame" => "...base64..."}
  """
  @spec receive_push(GenServer.server(), map()) :: :ok | {:error, term()}
  def receive_push(bridge, payload) when is_map(payload) do
    GenServer.call(bridge, {:receive_push, payload})
  end

  def send_frame(bridge, peer_id, frame, opts \\ []) when is_binary(frame) do
    GenServer.call(bridge, {:send_frame, peer_id, frame, opts})
  end

  def broadcast_frame(bridge, frame, opts \\ []) when is_binary(frame) do
    GenServer.call(bridge, {:broadcast_frame, frame, opts})
  end

  def stop(bridge), do: GenServer.stop(bridge)

  @impl true
  def init(opts) do
    event_target = Keyword.fetch!(opts, :event_target)
    config = Keyword.get(opts, :config, Application.get_env(:mob_cellular, :config, []))

    state = %{
      event_target: event_target,
      config: config,
      push_client: Keyword.get(opts, :push_client),
      max_payload_bytes:
        Keyword.get(opts, :max_payload_bytes, config_value(config, :max_payload_bytes)) ||
          @default_payload_budget
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send_frame, peer_id, frame, opts}, _from, state) do
    envelope = frame_envelope(peer_id, frame, opts)

    reply =
      with :ok <- check_payload_size(envelope, state.max_payload_bytes),
           :ok <- deliver(state.push_client, peer_id, envelope, opts) do
        :ok
      end

    {:reply, reply, state}
  end

  def handle_call({:broadcast_frame, frame, opts}, _from, state) do
    recipients = Keyword.get(opts, :recipients, [])

    reply =
      if recipients == [] do
        {:error, :recipients_required}
      else
        recipients
        |> Enum.map(&send_one(&1, frame, opts, state))
        |> Enum.find(:ok, &match?({:error, _}, &1))
      end

    {:reply, reply, state}
  end

  def handle_call({:receive_push, payload}, _from, state) do
    reply =
      case decode_envelope(payload) do
        {:ok, {:frame, peer_id, frame, metadata}} ->
          send(state.event_target, {:frame, peer_id, frame})

          if map_size(metadata) > 0 do
            send(state.event_target, {:transport_up, peer_id, metadata})
          end

          :ok

        {:ok, {:peer_up, peer_id, metadata}} ->
          send(state.event_target, {:transport_up, peer_id, metadata})
          :ok

        {:ok, {:peer_down, peer_id}} ->
          send(state.event_target, {:transport_down, peer_id})
          :ok

        {:error, reason} ->
          send(state.event_target, {:transport_error, reason})
          {:error, reason}
      end

    {:reply, reply, state}
  end

  defp send_one(peer_id, frame, opts, state) do
    envelope = frame_envelope(peer_id, frame, opts)

    with :ok <- check_payload_size(envelope, state.max_payload_bytes) do
      deliver(state.push_client, peer_id, envelope, opts)
    end
  end

  defp require_event_target(opts) do
    case Keyword.fetch(opts, :event_target) do
      {:ok, pid} when is_pid(pid) -> :ok
      {:ok, other} -> {:error, {:invalid_event_target, other}}
      :error -> {:error, {:missing_required_option, :event_target}}
    end
  end

  defp validate_start_config(opts) do
    config = Keyword.get(opts, :config, Application.get_env(:mob_cellular, :config, []))

    case Mob.Cellular.validate_config(config) do
      :ok -> validate_carrier!(Keyword.get(opts, :carrier, config_value(config, :carrier)))
      err -> raise "mob_cellular validate_config failed: #{inspect(err)}"
    end
  end

  defp validate_carrier!(nil), do: :ok
  defp validate_carrier!(:push), do: :ok

  defp validate_carrier!(:sms) do
    raise Mob.Cellular.CarrierRejectedError,
      carrier: :sms,
      reason: :sms_bridge_not_implemented
  end

  defp validate_carrier!(carrier) do
    raise Mob.Cellular.CarrierRejectedError,
      carrier: carrier,
      reason: :unsupported_carrier
  end

  defp frame_envelope(peer_id, frame, opts) do
    metadata =
      opts
      |> Keyword.get(:metadata, %{})
      |> normalize_metadata()

    %{
      "v" => @envelope_version,
      "type" => "frame",
      "peer_id" => to_string(peer_id),
      "frame" => Base.encode64(frame),
      "metadata" => metadata
    }
  end

  defp decode_envelope(payload) do
    with {:ok, version} <- fetch_value(payload, :v),
         :ok <- require_version(version),
         {:ok, type} <- fetch_value(payload, :type) do
      decode_type(to_string(type), payload)
    end
  end

  defp decode_type("frame", payload) do
    with {:ok, peer_id} <- fetch_value(payload, :peer_id),
         {:ok, encoded_frame} <- fetch_value(payload, :frame),
         {:ok, frame} <- Base.decode64(to_string(encoded_frame)) do
      {:ok, {:frame, to_string(peer_id), frame, metadata(payload)}}
    else
      :error -> {:error, :invalid_base64_frame}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_type("peer_up", payload) do
    with {:ok, peer_id} <- fetch_value(payload, :peer_id) do
      {:ok, {:peer_up, to_string(peer_id), metadata(payload)}}
    end
  end

  defp decode_type("peer_down", payload) do
    with {:ok, peer_id} <- fetch_value(payload, :peer_id) do
      {:ok, {:peer_down, to_string(peer_id)}}
    end
  end

  defp decode_type(type, _payload), do: {:error, {:unknown_push_type, type}}

  defp fetch_value(map, key) do
    cond do
      Map.has_key?(map, key) -> {:ok, Map.fetch!(map, key)}
      Map.has_key?(map, to_string(key)) -> {:ok, Map.fetch!(map, to_string(key))}
      true -> {:error, {:missing_required_key, key}}
    end
  end

  defp require_version(@envelope_version), do: :ok
  defp require_version(version), do: {:error, {:unsupported_envelope_version, version}}

  defp metadata(payload) do
    payload
    |> value(:metadata, %{})
    |> normalize_metadata()
  end

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_metadata), do: %{}

  defp value(map, key, default) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp check_payload_size(envelope, max_payload_bytes) do
    bytes = :erlang.external_size(envelope)

    if bytes <= max_payload_bytes do
      :ok
    else
      {:error, {:payload_too_large, bytes, max_payload_bytes}}
    end
  end

  defp deliver(nil, _peer_id, _envelope, _opts), do: {:error, :push_client_not_configured}

  defp deliver(client, peer_id, envelope, opts) do
    apply(client, :deliver, [peer_id, envelope, opts])
  rescue
    error in UndefinedFunctionError ->
      Logger.error("mob_cellular push client is invalid: #{Exception.message(error)}")
      {:error, {:invalid_push_client, client}}
  end

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, to_string(key))
  end

  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(_config, _key), do: nil
end
