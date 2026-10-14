defmodule StarView.Page.PlugTest.MisbehavingStreamPage do
  use StarView.Page, idle_check: 50

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="m">misbehaving</div>'

  @impl StarView.Page
  def handle_connect(conn, _params) do
    send(:star_view_page_plug_stream_test, {:connected, self()})
    conn
  end

  # LiveView muscle memory — must be rejected loudly, not threaded as conn.
  @impl StarView.Page
  def handle_info(:bad_return, conn), do: {:noreply, conn}

  # A FunctionClauseError raised INSIDE a matched clause (module != page)
  # must propagate, not be absorbed as an unhandled stray.
  def handle_info({:fce_inside, value}, _conn), do: String.split(value, "x")

  def handle_info(:recursive_fce, conn), do: handle_info(:missing_nested_clause, conn)
end
