defmodule StarView.Signals.ReadError do
  @moduledoc "Raised when Datastar signals cannot be decoded from a request."

  defexception [:reason]

  @impl Exception
  def message(%__MODULE__{reason: reason}),
    do: "failed to read Datastar signals: #{inspect(reason)}"
end
