defmodule StarView.ComponentTest.DetailDrawer do
  use StarView.Component

  def drawer(assigns) do
    ~H"""
    <div id="item-detail-drawer">
      <input data-on:change={event("change_title:#{@item.id}")} value={@item.title} />
    </div>
    """
  end

  def handle_event("change_title:" <> _id, signals, conn) do
    # SSE is already started by StarView.Dispatch.
    patch_signals(conn, %{saved: true, title: signals["title"]})
  end
end
