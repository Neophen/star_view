defmodule StarView.PageTest.TunedPage do
  use StarView.Page, idle_check: 50

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="t">tuned</div>'
end
