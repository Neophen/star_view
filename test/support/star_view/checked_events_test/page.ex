defmodule StarView.CheckedEventsTest.Page do
  @moduledoc false
  use StarView.Page, checked_events: true

  import StarView.Template.Sigils

  @impl StarView.Page
  def render(assigns) do
    ~STAR"""
    <main id="checked-page">
      <button data-on:click={event("save")}>Save</button>
      <button data-on:click={event("read", verb: :get)}>Read</button>
    </main>
    """
  end

  @impl StarView.Page
  def handle_event("save", _signals, %{method: "POST"} = conn) do
    conn
    |> notify(:saved)
    |> patch_signals(%{saved: true})
  end

  def handle_event("read", _signals, %{method: "GET"} = conn), do: notify(conn, :read)
  def handle_event(event, _signals, conn), do: notify(conn, {:fallback, event})

  defp notify(conn, message) do
    send(self(), {:checked_event, __MODULE__, message})
    conn
  end
end
