defmodule Mob.Cellular.CarrierRejectedError do
  @moduledoc """
  Raised when a caller asks `Mob.Cellular` to use an unsupported carrier.
  """

  defexception [:carrier, :reason]

  @type t :: %__MODULE__{carrier: atom() | term(), reason: atom() | binary() | nil}

  @impl true
  def message(%__MODULE__{carrier: carrier, reason: reason}) do
    """
    Mob.Cellular: carrier #{inspect(carrier)} is rejected.

    Reason: #{inspect(reason || :unsupported_carrier)}
    Supported carriers are #{inspect(Mob.Cellular.Config.supported_carriers())}.
    The primary carrier is #{inspect(Mob.Cellular.carrier())}.
    """
  end
end
