defmodule StarView.Documentation.Orders do
  @moduledoc false

  # Application boundary used by the compiled guide; no database is needed.
  def list_for(scope), do: scope.orders

  def authorized_list(%{allowed?: false}), do: {:error, :forbidden}
  def authorized_list(scope), do: {:ok, list_for(scope)}
end
