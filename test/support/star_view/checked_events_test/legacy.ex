defmodule StarView.CheckedEventsTest.Legacy do
  @moduledoc false
  use StarView, auto_render: false

  @impl StarView
  def mount(conn, _params), do: conn

  @impl StarView
  def render(_assigns), do: ""

  @impl StarView
  def handle_event(event, _signals, conn) do
    send(self(), {:checked_event, __MODULE__, {event, conn.method}})
    conn
  end
end
