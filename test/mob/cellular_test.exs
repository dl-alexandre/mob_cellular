defmodule Mob.CellularTest do
  use ExUnit.Case, async: true

  alias Mob.Cellular.CarrierRejectedError

  describe "public API" do
    test "uses push as primary carrier" do
      assert Mob.Cellular.carrier() == :push
      assert Mob.Cellular.bridge_module() == Mob.Cellular.PushBridge
      assert Mob.Cellular.default_bridge() == Mob.Cellular.PushBridge
    end
  end

  describe "validate_config/1" do
    test "accepts empty and push configs" do
      assert :ok = Mob.Cellular.validate_config([])
      assert :ok = Mob.Cellular.validate_config(%{})
      assert :ok = Mob.Cellular.validate_config(carrier: :push)
    end

    test "accepts sms as manifest-level future fallback" do
      assert :ok = Mob.Cellular.validate_config(carrier: :sms)
    end

    test "rejects unsupported carriers" do
      assert_raise CarrierRejectedError, fn ->
        Mob.Cellular.validate_config(carrier: :direct_cellular_data)
      end
    end

    test "validates known typed options" do
      assert :ok = Mob.Cellular.validate_config(push_providers: [:fcm, :apns])

      assert {:error, {:invalid_config, :push_providers, [:smtp]}} =
               Mob.Cellular.validate_config(push_providers: [:smtp])

      assert {:error, {:invalid_config, :max_payload_bytes, 0}} =
               Mob.Cellular.validate_config(max_payload_bytes: 0)

      assert {:error, {:invalid_config, :log_level, "info"}} =
               Mob.Cellular.validate_config(log_level: "info")

      assert {:error, {:invalid_config, :native?, "false"}} =
               Mob.Cellular.validate_config(native?: "false")
    end
  end
end
