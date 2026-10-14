defmodule StarView.Page.PlugTest.KeyedStreamPage do
  use StarView.Page, idle_check: 50

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="k">keyed</div>'

  @impl StarView.Page
  def stream_key(_conn), do: :test_scope

  @impl StarView.Page
  def handle_connect(conn, _params) do
    send(:star_view_page_plug_stream_test, {:keyed_connected, self()})
    conn
  end

  @impl StarView.Page
  def handle_info(:halt_now, conn), do: {:halt, conn}
end
