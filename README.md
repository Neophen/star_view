<p align="center">
  <img src="https://raw.githubusercontent.com/Neophen/star_view/main/assets/logo.png" alt="StarView logo" width="128" />
</p>

# StarView - Unofficial helpers for Datastar and Phoenix

### THIS IS IN ALPHA STAGES EVERYTHING CHANGES DAILY DO NOT USE

<p align="center">
  <a href="https://hexdocs.pm/star_view">
    <img src="https://img.shields.io/github/v/release/Neophen/star_view?color=lawn-green" alt="Version" />
  </a>
  <a href="https://hex.pm/packages/star_view">
    <img src="https://img.shields.io/hexpm/dw/star_view?style=flat&label=downloads&color=blue" alt="Downloads" />
  </a>
  <img src="https://img.shields.io/badge/Erlang/OTP-27+-blue" alt="Requires Erlang/OTP 27+" />
  <a href="https://github.com/Neophen/star_view/blob/main/LICENSE">
    <img src="https://img.shields.io/github/license/Neophen/star_view" alt="License" />
  </a>
</p>

StarView is an Elixir SDK for [Datastar](https://data-star.dev) Server-Sent Events.
It works with Plug and Phoenix, and uses Erlang's built-in `:json` module.

## The Problem

Building Datastar apps in Elixir means a lot of boilerplate. You manually start
SSE connections, track which values to send to the browser, and remember to
flush them at the end. It's easy to forget a step.

StarView removes that.

## What Makes It Different

**`signal/3` does two things at once.**

It sets a connection assign (so your function components can read it) **and**
patches it to the browser automatically during Datastar requests.

```elixir
def handle_event("increment", signals, conn) do
  conn
  # Server-only: function components can read @computed_value, browser never sees it
  |> assign(:computed_value, expensive_calculation(signals))
  # Both: function components can read @count, browser gets it too
  |> signal(:count, signals["count"] + 1)
  # Render a function component and patch it into the DOM
  |> patch_element(&history_item/1, to: "history-list", mode: :append)
  # If the function component has an id you can simplify this code to just
  |> patch_element(&history_item/1)
end
```

**No manual start or signal patching.**

The dispatch plug starts the SSE response before your handler runs. `signal/3`
then assigns the value and sends the Datastar signal patch immediately.

**Auto-registration.**

Any controller that `use StarView` is automatically dispatchable.
No allow-list in your router to maintain.

## Installation

### Quick (Igniter)

```bash
mix igniter.install star_view
```

This sets up the StarView Phoenix development flow out of the box:

- Adds the dependency.
- Adds `StarView.StreamRegistry` to your supervision tree.
- Adds a dedicated `star_view` section to your web module after `controller`.
- Generates `YourAppWeb.Components.StarView.Layout` for the StarView document
  layout and page wrapper.
- Configures HTTPS and `https://<hyphenated-otp-app>.test:4001` as the dev URL.
- Provides `mix star_view.trust` to add the local host entry and generate a
  browser-trusted HTTPS certificate with `mkcert`.
- Patches your router with `/search` and `/ds/:module/:event` routes.
- Generates a sample search controller.
- Provides `mix dev`, which delegates to `mix star_view.server`.

Install `mkcert` first:

```bash
brew install mkcert nss
```

Then run the trust step directly after installation:

```bash
mix star_view.trust
```

It adds the `.test` host to `/etc/hosts`, runs `mkcert -install`, and writes
`priv/cert/selfsigned.pem` plus `priv/cert/selfsigned_key.pem`. It may prompt
for sudo privileges. Run it before `mix dev` so Phoenix can find the configured
certificate files.

Skip parts you don't want:

```bash
mix igniter.install star_view --no-stream-dedup --no-https --no-example
```

Start Phoenix and open the configured dev URL:

```bash
mix dev
```

### Manual

```elixir
def deps do
  [
    {:star_view, "~> 0.3.18"}
  ]
end
```

Add `StarView.StreamRegistry` to your supervision tree if you want
per-tab stream deduplication.

Add a `star_view` section to your web module. Place it after the existing
`controller` section so controller-style helpers stay grouped together:

```elixir
def star_view do
  quote do
    use Phoenix.Controller, formats: [:html, :json]
    use StarView
    use Phoenix.Component

    use Gettext, backend: MyAppWeb.Gettext

    import Phoenix.Component, except: [assign: 3]
    import Plug.Conn

    alias MyAppWeb.Components.StarView.Layout

    plug :put_root_layout, false

    unquote(verified_routes())
  end
end
```

Create `MyAppWeb.Components.StarView.Layout` for the document layout and
`Layout.app/1` wrapper. The Igniter installer generates this from
`priv/templates/layout.eex`.

Add the dispatch route to your router:

```elixir
pipeline :browser do
  # ...
  plug StarView.Plug.RenameCsrfParam
  plug :protect_from_forgery
  # ...
end

scope "/", MyAppWeb do
  pipe_through :browser
  post "/ds/:module/:event", StarView.Dispatch, [], alias: false
end
```

`alias: false` keeps Phoenix from resolving the dispatch plug as
`MyAppWeb.StarView.Dispatch` inside the scoped router block.
`StarView.Plug.RenameCsrfParam` must run before `:protect_from_forgery` so
Datastar's `csrf` signal is available as Phoenix's `_csrf_token` parameter.

## Phoenix Setup

Write a controller with the `:star_view` web-module section:

```elixir
defmodule MyAppWeb.CounterController do
  use MyAppWeb, :star_view

  # Called on page load. Set up initial signals here.
  @impl StarView
  def mount(conn, _params) do
    conn
    |> signal(:count, 0)
  end

  # Render the initial HTML. Layout.app sends starting signal values to the browser.
  @impl StarView
  def render(assigns) do
    ~H"""
    <Layout.app conn={@conn}>
      <button data-on:click={post("increment")}>+</button>
      <span data-text="$count">{@count}</span>
    </Layout.app>
    """
  end

  # Called when the user clicks the button. Return the updated conn.
  @impl StarView
  def handle_event("increment", signals, conn) do
    signal(conn, :count, Map.get(signals, "count", 0) + 1)
  end
end
```

That's it. The dispatcher handles SSE start, calls your handler, and `signal/3`
sends browser-visible values as your pipeline runs.

## `assign` vs `signal`

| Function | Function components see it | Browser sees it |
|---|---|---|
| `assign(conn, :key, value)` | Yes | No |
| `signal(conn, :key, value)` | Yes | Yes (initially or immediately during SSE) |

Use `assign` for server-only data you pass to components. Use `signal` for
anything the browser needs to react to.

## Patching Function Components

`patch_element/3` renders a function component against current assigns and sends
the HTML to the browser:

```elixir
def handle_event("add_item", _signals, conn) do
  conn
  |> assign(:items, ["Ada", "Grace"])
  |> patch_element(&list/1, to: "people", mode: :replace)
end
```

Pass a function of arity 1 and it receives the assigns map. Pass raw HTML and
it sends that directly.

## Per-Tab Stream Deduplication

When a user navigates away, the old SSE process can stick around until the next
keepalive. That wastes connections. StarView can kill the old stream when a new
one starts from the same tab.

Add this to your supervision tree:

```elixir
children = [
  StarView.StreamRegistry,
  # ...
]
```

Set a `tabId` signal in your layout:

```heex
<div data-signals={~s({"tabId": "#{Ecto.UUID.generate()}"})}>
```

Start streams with:

```elixir
conn = StarView.start_stream(conn, current_user.id)
```

If no `tabId` is present, it falls back to a regular stream with no deduplication.

## CSRF (Forms)

You usually don't need forms with Datastar. If you do, put the CSRF token in a
`csrf` signal and add this plug before your CSRF protection:

```elixir
plug StarView.Plug.RenameCsrfParam
plug :protect_from_forgery
```

## Migration from Dstar

| Dstar | StarView |
|---|---|
| `Dstar` | `StarView` |
| `Dstar.Utility.StreamRegistry` | `StarView.StreamRegistry` |
| `$_dstar_module` | `$_star_view_module` |
| `Dstar.read_signals/1` | `StarView.read_signals/1` |
| Manual `Dstar.start/1` | Handled by dispatch plug |
| Manual signal patching | Handled by `signal/3` |

## Full API

```elixir
StarView.start(conn)
StarView.start_stream(conn, user_id)
StarView.check_connection(conn)
StarView.patch_elements(conn, html, selector: "#target", mode: :replace)
StarView.remove_elements(conn, "#target")
StarView.patch_signals(conn, %{count: 1})
StarView.patch_signals_raw(conn, ~s({"count":1}))
StarView.remove_signals(conn, ["user.email"])
StarView.execute_script(conn, "console.log('done')")
StarView.redirect(conn, "/next")
StarView.console_log(conn, "debug")
StarView.read_signals(conn)
```
