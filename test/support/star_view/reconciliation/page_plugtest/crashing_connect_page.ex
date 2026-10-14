defmodule StarView.Page.PlugTest.CrashingConnectPage do
  use StarView.Page

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="cc">never</div>'

  @impl StarView.Page
  def handle_connect(_conn, _params) do
    raise "connect exploded"
  end
end
