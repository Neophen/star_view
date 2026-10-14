defmodule StarView.RouterTest.CounterPage do
  use StarView.Page

  @impl StarView.Page
  def mount(conn, _params), do: assign(conn, count: 0)

  @impl StarView.Page
  def render(assigns) do
    ~H"""
    <div data-signals:count={@count}>counter</div>
    """
  end

  @impl StarView.Page
  def handle_event("increment", signals, conn) do
    patch_signals(conn, %{count: (signals["count"] || 0) + 1})
  end

  def handle_event("remove", _signals, conn) do
    patch_signals(conn, %{removed: true})
  end
end
