defmodule Mob.Cellular do
  @moduledoc """
  Cellular fallback transport plugin for `mob`.

  `mob_cellular` is designed for last-resort, always-reachable messaging when
  local transports such as BLE, WiFi, or mesh links are unavailable. The initial
  implementation uses push-notification envelopes and delegates provider
  delivery to an injected push client, keeping FCM/APNs credentials out of the
  generic transport process.
  """

  alias Mob.Cellular.Config

  @doc "Returns the active primary carrier."
  @spec carrier() :: :push
  def carrier, do: :push

  @doc "Returns the transport implementation module for plugin activation."
  @spec bridge_module() :: module()
  def bridge_module, do: Mob.Cellular.PushBridge

  @doc "Transitional alias for `bridge_module/0`."
  @spec default_bridge() :: module()
  def default_bridge, do: bridge_module()

  @doc """
  Validates deployment configuration.

  Unknown keys are tolerated for forward compatibility. Unsupported carriers
  raise `Mob.Cellular.CarrierRejectedError`.
  """
  @spec validate_config(keyword() | map()) :: :ok | {:error, term()}
  def validate_config(config) when is_list(config) or is_map(config) do
    Config.validate(config)
  end
end
