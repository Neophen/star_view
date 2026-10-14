defmodule StarView.Page.PlugTest.DeadAdapter do
  def chunk(_state, _body), do: {:error, :closed}
end
