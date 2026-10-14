defmodule StarView.RouterTest.ReadPage do
  use StarView.Page

  @impl StarView.Page
  def render(assigns), do: ~H"<div id='read-only'></div>"

  @impl StarView.Page
  def handle_event("read", _signals, %{method: "GET"} = conn),
    do: patch_signals(conn, %{read: true})

  def handle_event(_event, _signals, conn), do: conn
end
