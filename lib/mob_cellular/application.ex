defmodule MobCellular.Application do
  @moduledoc """
  OTP Application for the `mob_cellular` plugin.

  The application validates deployment configuration and starts an internal
  supervisor anchor. `Mob.Cellular.PushBridge` instances are intentionally
  owned by the caller's transport adapter so each bridge gets the correct
  `:event_target`.
  """

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    config = Application.get_env(:mob_cellular, :config, [])
    Logger.info("mob_cellular starting with config: #{inspect(config)}")

    case Mob.Cellular.validate_config(config) do
      :ok -> :ok
      err -> raise "mob_cellular validate_config failed: #{inspect(err)}"
    end

    Supervisor.start_link([], strategy: :one_for_one, name: MobCellular.Supervisor)
  end

  @impl true
  def stop(_state) do
    Logger.info("mob_cellular stopping")
    :ok
  end
end
