defmodule StarView.Page.PlugTest.RedirectPage do
  use StarView.Page

  @impl StarView.Page
  def mount(conn, _params) do
    conn
    |> Plug.Conn.put_resp_header("location", "/login")
    |> Plug.Conn.send_resp(302, "")
  end

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="never">never rendered</div>'
end
