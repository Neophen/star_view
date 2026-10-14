defmodule StarView.Page.PlugTest.StreamPage do
  use StarView.Page, idle_check: 50

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="s">stream</div>'

  @impl StarView.Page
  def handle_connect(conn, _params) do
    send(:star_view_page_plug_stream_test, {:connected, self()})
    conn
  end

  @impl StarView.Page
  def handle_info({:tick, n}, conn), do: patch_signals(conn, %{tick: n})

  def handle_info({:ping, from}, conn) do
    send(from, :pong)
    conn
  end

  def handle_info(:halt_now, conn), do: {:halt, conn}
end
