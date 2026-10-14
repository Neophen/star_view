defmodule StarView.SSE.TransportError do
  @moduledoc "Raised when the Plug adapter rejects an SSE write."

  defexception [:reason, :conn]

  @impl Exception
  def message(%__MODULE__{reason: reason}), do: "failed to send SSE event: #{inspect(reason)}"

  @doc "True for a closed or reset client connection; other adapter failures propagate."
  @spec disconnected?(Exception.t()) :: boolean()
  def disconnected?(%__MODULE__{reason: reason}), do: reason in [:closed, :econnreset, :epipe]
end
