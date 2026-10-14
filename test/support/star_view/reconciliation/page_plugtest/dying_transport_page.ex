defmodule StarView.Page.PlugTest.DyingTransportPage do
  use StarView.Page, idle_check: 50

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="d">dying</div>'

  @impl StarView.Page
  def handle_connect(conn, _params) do
    send(:star_view_page_plug_stream_test, {:connected, self()})
    conn
  end

  @impl StarView.Page
  def handle_info(:kill_transport, conn) do
    {_adapter, state} = conn.adapter
    %{conn | adapter: {StarView.Page.PlugTest.DeadAdapter, state}}
  end

  def handle_info({:ping, from}, conn) do
    send(from, :pong)
    conn
  end
end
