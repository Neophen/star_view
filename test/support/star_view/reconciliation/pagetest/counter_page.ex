defmodule StarView.PageTest.CounterPage do
  use StarView.Page

  @impl StarView.Page
  def mount(conn, _params) do
    conn
    |> assign(count: 0)
    |> assign_new(:title, fn -> "Counter" end)
    |> update(:count, & &1)
  end

  @impl StarView.Page
  def render(assigns) do
    ~H"""
    <div data-signals:count={@count}>
      <button data-on:click={event("increment")}>+1</button>
    </div>
    """
  end

  @impl StarView.Page
  def handle_event("increment", signals, conn) do
    count = (signals["count"] || 0) + 1

    conn
    |> patch_signals(%{count: count})
    |> patch(&history/1, value: count)
  end

  defp history(assigns) do
    ~H"""
    <span id="history">Last: {@value}</span>
    """
  end
end
