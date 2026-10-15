# Overview

StarView is an Elixir SDK for [Datastar](https://data-star.dev) Server-Sent
Events. It works with Plug and Phoenix, and uses Erlang's built-in `:json`
module.

## The Problem

Building Datastar apps in Elixir can mean a lot of repeated wiring. You start
SSE responses, track which values need to reach the browser, render updated
HTML, and keep event handlers mapped to the modules that own them.

StarView keeps that flow close to normal Phoenix controller code.

## What StarView Adds

`signal/3` sets a connection assign and exposes the same value as a Datastar
signal. Function components can read the assign, while the browser receives the
signal during the initial render or immediately during an SSE event.

```elixir
def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
    when is_integer(count) and count >= 0 and count < 1_000_000 do
  conn
  |> Plug.Conn.assign(:label, "Count")
  |> signal(:count, count + 1)
  |> patch_element(&summary/1)
end
```

The submitted count is UI state in this example, not an authorized persisted
record. The [complete counter guide](../examples/phoenix_counter.md) includes
its component, initial render, and invalid-input path.

## Dispatch Flow

The Phoenix dispatcher starts the SSE response before your handler runs. Your
controller handles the event and returns the updated connection:

```elixir
@impl StarView
def handle_event("refresh", _signals, conn) do
  signal(conn, :refresh_complete, true)
end
```

Any controller that uses `use StarView` is automatically dispatchable through
`StarView.Dispatch`, so you do not maintain an allow-list for Phoenix
controllers.

## Next Steps

Start with the installation guide, then add the Phoenix web module section and
routes. Once the app is running, the core guides cover `patch_signals/3`,
`patch_element/3`, and optional per-tab stream deduplication.

## Choose the rendering and state boundary

Default to server-rendered HEEx with ordinary Datastar signals for form values,
visibility, and small reactive controls. A widget that owns timers, drag state,
external browser integrations, or repeated independent instances may benefit
from [Rocket](https://data-star.dev/reference/rocket), Datastar's beta custom-element
API with scoped client state and lifecycle hooks.

This is an application design choice: use props for the widget's public inputs
and local state for its internal interaction. Keep business writes and policies
on the server. Check the exact Rocket client you bundle before adopting its beta
API; StarView's release does not establish a Rocket version or supply its assets.

The optional `StarView.Page`, `StarView.Component` and `StarView.Router` APIs
are available alongside existing controllers. Use the integration that fits
the application's rendering boundary; adopting Datastar does not require
rewriting its backend or controller pages.

Read [Thinking in Phoenix, Datastar and StarView](mental_model.md) for the
request, state and backend model, including the ideas we took from Jacob
O'Bryant's Biff implementation.

For concrete workflows, read the [manual Plug endpoint](../examples/plug_endpoints.md),
[PubSub stream](../examples/pubsub_stream.md), [safe action](../core/actions.md),
and [troubleshooting](../reference/troubleshooting.md) guides.
