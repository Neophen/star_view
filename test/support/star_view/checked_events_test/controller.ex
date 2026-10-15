defmodule StarView.CheckedEventsTest.Controller do
  @moduledoc false
  use StarView, checked_events: true, auto_render: false
  use Phoenix.Component

  import StarView.Template.Sigils

  @impl StarView
  def mount(conn, _params), do: conn

  # The template sits above the handlers on purpose: references are checked
  # once the whole module is known.
  @impl StarView
  def render(assigns) do
    ~STAR"""
    <section id="actions">
      <button data-on:click={post("save")}>Save</button>
      <button data-on:click={delete("remove")}>Remove</button>
      <button data-on:click={patch("remove")}>Archive</button>
      <button data-on:click={get("read")}>Read</button>
    </section>
    """
  end

  @impl StarView
  def handle_event("save", %{"count" => count}, %{method: "POST"} = conn)
      when is_integer(count) do
    conn
    |> notify({:saved, count})
    |> StarView.patch_signals(%{count: count + 1})
  end

  def handle_event("save", _signals, %{method: "POST"} = conn) do
    conn
    |> notify(:invalid_save)
    |> StarView.patch_signals(%{error: "count must be an integer"})
  end

  def handle_event("remove", _signals, %Plug.Conn{method: "DELETE"} = conn),
    do: notify(conn, :removed)

  def handle_event("remove", _signals, %{method: "PATCH"} = conn), do: notify(conn, :archived)
  def handle_event("read", _signals, %{method: "GET"} = conn), do: notify(conn, :read)
  def handle_event(event, _signals, conn), do: notify(conn, {:fallback, event})

  defp notify(conn, message) do
    send(self(), {:checked_event, __MODULE__, message})
    conn
  end
end
