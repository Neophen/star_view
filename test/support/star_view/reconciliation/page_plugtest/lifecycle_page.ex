defmodule StarView.Page.PlugTest.LifecyclePage do
  use StarView.Page, idle_check: 10

  @impl StarView.Page
  def render(assigns), do: ~H"<div id='lifecycle'></div>"

  @impl StarView.Page
  def stream_key(conn), do: conn.assigns.topic

  @impl StarView.Page
  def handle_connect(conn, params) do
    Phoenix.PubSub.subscribe(conn.assigns.pubsub, conn.assigns.topic)
    send(conn.assigns.test_pid, {:connected, self(), params})
    finish_connect(conn, conn.assigns.fail_connect)
  end

  defp finish_connect(_conn, true), do: raise("connect failed")
  defp finish_connect(conn, false), do: assign(conn, :phase, :connected)

  @impl StarView.Page
  def handle_info({:phase, value}, conn), do: assign(conn, :phase, value)

  def handle_info({:phase, value, from}, conn) do
    conn = assign(conn, :phase, value)
    send(from, {:phase_changed, self(), value})
    conn
  end

  def handle_info(:closed_write, conn) do
    conn = assign(conn, :phase, :unfinished_write)
    conn = %{conn | adapter: {StarView.TransportAdapter, {:error, :closed}}}
    patch_signals(conn, %{saved: true})
  end

  def handle_info(:crash, _conn), do: raise("message failed")
  def handle_info(:halt, conn), do: {:halt, assign(conn, :phase, :halted)}

  @impl StarView.Page
  def handle_disconnect(conn) do
    Phoenix.PubSub.unsubscribe(conn.assigns.pubsub, conn.assigns.topic)
    owner = StarView.StreamRegistry.owner({conn.assigns.topic, "lifecycle-tab"})
    send(conn.assigns.test_pid, {:disconnected, self(), conn.assigns.phase, owner})
    finish_disconnect(conn.assigns.fail_disconnect)
  end

  defp finish_disconnect(true), do: raise("cleanup failed")
  defp finish_disconnect(false), do: :ok
end
