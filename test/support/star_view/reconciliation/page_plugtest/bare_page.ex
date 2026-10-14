defmodule StarView.Page.PlugTest.BarePage do
  use StarView.Page

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="bare">bare</div>'
end
