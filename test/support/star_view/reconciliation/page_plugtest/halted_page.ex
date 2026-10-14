defmodule StarView.Page.PlugTest.HaltedPage do
  use StarView.Page

  @impl StarView.Page
  def mount(conn, _params) do
    conn
    |> Plug.Conn.send_resp(401, "unauthorized")
    |> Plug.Conn.halt()
  end

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="never-halted">never rendered</div>'
end
