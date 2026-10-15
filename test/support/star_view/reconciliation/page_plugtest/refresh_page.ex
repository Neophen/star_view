defmodule StarView.Page.PlugTest.RefreshPage do
  use StarView.Page, idle_check: 50, refresh_interval: 0

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="refresh">refresh</div>'

  @impl StarView.Page
  def handle_connect(conn, _params) do
    send(conn.assigns.test_pid, {:refresh_connected, self()})
    assign(conn, version: 0, renders: 0)
  end

  @impl StarView.Page
  def handle_info({:changed, version}, conn),
    do: conn |> assign(:version, version) |> StarView.invalidate()

  def handle_info({:hold, from}, conn) do
    send(from, {:held, self()})
    await_release(conn)
  end

  defp await_release(conn) do
    receive do
      :release -> conn
    end
  end

  @impl StarView.Page
  def handle_refresh(%{assigns: %{version: :stop}} = conn), do: {:halt, conn}
  def handle_refresh(%{assigns: %{version: :raise}}), do: raise("refresh failed")
  def handle_refresh(%{assigns: %{version: :bad_return}}), do: :bad_return

  def handle_refresh(conn) do
    conn = update(conn, :renders, &(&1 + 1))
    send(conn.assigns.test_pid, {:refreshed, self(), conn.assigns.version, conn.assigns.renders})
    patch(conn, &content/1, [version: conn.assigns.version], key: :content, only_changed: true)
  end

  @impl StarView.Page
  def handle_disconnect(conn) do
    send(conn.assigns.test_pid, {:refresh_disconnected, self(), conn.assigns.version})
  end

  def content(assigns), do: ~H'<div id="content">{@version}</div>'
end
