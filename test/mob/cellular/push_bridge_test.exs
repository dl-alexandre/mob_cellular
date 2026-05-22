defmodule Mob.Cellular.PushBridgeTest do
  use ExUnit.Case, async: true

  alias Mob.Cellular.CarrierRejectedError
  alias Mob.Cellular.PushBridge

  defmodule PushClient do
    @moduledoc false

    def deliver(peer_id, envelope, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:push_delivered, peer_id, envelope})
      :ok
    end
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

      GenServer.stop(bridge)
    end

    test "returns an error when no push client is configured" do
      {:ok, bridge} = PushBridge.start_link(event_target: self())

      assert {:error, :push_client_not_configured} =
               PushBridge.send_frame(bridge, "peer-1", "hello")

      GenServer.stop(bridge)
    end

    test "broadcast requires explicit recipients" do
      {:ok, bridge} = PushBridge.start_link(event_target: self(), push_client: PushClient)

      assert {:error, :recipients_required} = PushBridge.broadcast_frame(bridge, "hello")

      assert :ok =
               PushBridge.broadcast_frame(bridge, "hello",
                 recipients: ["a", "b"],
                 test_pid: self()
               )

      assert_receive {:push_delivered, "a", _}
      assert_receive {:push_delivered, "b", _}

      GenServer.stop(bridge)
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

      GenServer.stop(bridge)
    end
  end
end
