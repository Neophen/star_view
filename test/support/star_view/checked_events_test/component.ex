defmodule StarView.CheckedEventsTest.Component do
  @moduledoc false
  use StarView.Component, checked_events: true

  import StarView.Template.Sigils

  def panel(assigns) do
    ~STAR"""
    <div id="checked-panel"><button data-on:click={event("toggle")}>Toggle</button></div>
    """
  end

  def handle_event("toggle", _signals, %{method: "POST"} = conn) do
    send(self(), {:checked_event, __MODULE__, :toggled})
    patch_signals(conn, %{open: true})
  end
end
