defmodule Mob.Cellular.Config do
  @moduledoc """
  Configuration validation for `mob_cellular`.
  """

  @supported_carriers [:push, :sms]
  @supported_push_providers [:fcm, :apns]

  @doc "Returns carriers recognized by the plugin manifest."
  @spec supported_carriers() :: [:push | :sms]
  def supported_carriers, do: @supported_carriers

  @doc "Returns push providers recognized by the initial bridge."
  @spec supported_push_providers() :: [:fcm | :apns]
  def supported_push_providers, do: @supported_push_providers

  @doc false
  @spec validate(keyword() | map()) :: :ok | {:error, term()}
  def validate(config) do
    cfg = Map.new(Enum.to_list(config))

    with :ok <- check_carrier(cfg),
         :ok <- check_push_providers(cfg),
         :ok <- check_max_payload_bytes(cfg),
         :ok <- check_log_level(cfg) do
      check_native(cfg)
    end
  end

  defp check_carrier(%{carrier: carrier}) when carrier in @supported_carriers, do: :ok

  defp check_carrier(%{carrier: carrier}) do
    raise Mob.Cellular.CarrierRejectedError,
      carrier: carrier,
      reason: :unsupported_carrier
  end

  defp check_carrier(_cfg), do: :ok

  defp check_push_providers(%{push_providers: providers})
       when is_list(providers) and providers != [] do
    invalid = Enum.reject(providers, &(&1 in @supported_push_providers))

    case invalid do
      [] -> :ok
      _ -> {:error, {:invalid_config, :push_providers, providers}}
    end
  end

  defp check_push_providers(%{push_providers: providers}) do
    {:error, {:invalid_config, :push_providers, providers}}
  end

  defp check_push_providers(_cfg), do: :ok

  defp check_max_payload_bytes(%{max_payload_bytes: bytes})
       when is_integer(bytes) and bytes > 0 do
    :ok
  end

  defp check_max_payload_bytes(%{max_payload_bytes: bytes}) do
    {:error, {:invalid_config, :max_payload_bytes, bytes}}
  end

  defp check_max_payload_bytes(_cfg), do: :ok

  defp check_log_level(%{log_level: level}) when is_atom(level), do: :ok
  defp check_log_level(%{log_level: level}), do: {:error, {:invalid_config, :log_level, level}}
  defp check_log_level(_cfg), do: :ok

  defp check_native(%{native?: native?}) when is_boolean(native?), do: :ok
  defp check_native(%{native?: native?}), do: {:error, {:invalid_config, :native?, native?}}
  defp check_native(_cfg), do: :ok
end
