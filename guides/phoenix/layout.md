# StarView Layout

The Igniter installer generates a dedicated layout module for StarView
controllers. This manual variant uses the optional application-owned
`:star_component` entrypoint described in the [web module guide](web_module.md)
and loads Datastar through the application's asset bundle:

```elixir
defmodule MyAppWeb.Components.StarView.Layout do
  use MyAppWeb, :star_component

  attr :conn, :map, required: true
  attr :lang, :string, default: "en"
  attr :theme, :string, default: nil
  attr :body_attrs, :map, default: %{}

  slot :inner_block, required: true
  slot :head

  def app(assigns) do
    ~H"""
    <.root lang={@lang} theme={@theme} body_attrs={@body_attrs}>
      <:head :if={@head != []}>{render_slot(@head)}</:head>
      <main data-signals={init_signals(@conn)}>
        {render_slot(@inner_block)}
      </main>
    </.root>
    """
  end

  attr :conn, :map, required: true
  attr :lang, :string, default: "en"
  attr :theme, :string, default: nil
  attr :body_attrs, :map, default: %{}

  slot :inner_block, required: true
  slot :head

  def auth(assigns) do
    ~H"""
    <.root
      lang={@lang}
      theme={@theme}
      html_class="h-full bg-base-200"
      body_class="h-full"
      body_attrs={@body_attrs}
    >
      <:head :if={@head != []}>{render_slot(@head)}</:head>
      <main data-signals={init_signals(@conn)}>
        {render_slot(@inner_block)}
      </main>
    </.root>
    """
  end

  attr :lang, :string, default: "en"
  attr :theme, :string, default: nil
  attr :body_attrs, :map, default: %{}
  attr :html_class, :string, default: nil
  attr :body_class, :string, default: nil
  slot :inner_block, required: true
  slot :head

  defp root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@lang} class={@html_class} data-theme={@theme}>
      <head>
        <meta name="csrf-token" content={get_csrf_token()} />
        <script defer type="module" src={~p"/assets/js/app.js"} />
        {render_slot(@head)}
      </head>
      <body {csrf_signal()} {@body_attrs} class={@body_class}>
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end

  defp csrf_signal() do
    %{"data-signals:csrf" => "'#{get_csrf_token()}'"}
  end
end
```

The `:star_view` web-module section aliases that module and disables Phoenix's
root layout for StarView controllers:

```elixir
alias MyAppWeb.Components.StarView.Layout

plug :put_root_layout, false
```

## Layouts

Use `Layout.app/1` at the top of each StarView controller render:

```elixir
@impl StarView
def render(assigns) do
  ~H"""
  <Layout.app conn={@conn}>
    <button data-on:click={post("increment")}>+</button>
    <span data-text="$count"></span>
  </Layout.app>
  """
end
```

`Layout.auth/1` is a full-height variant used by the generated auth pages (see
the [auth guide](auth.md)). It sets `html_class`/`body_class` on the private
root component so auth screens can center their content vertically.

Both layouts write the initial signal payload with `init_signals/1`. The
private root component adds the CSRF token and Datastar script once for the
full page, and accepts `:theme` for daisyUI-style `data-theme` switching.

## Bundle the client once

Import the locally acquired Datastar ES module from `assets/js/app.js`, or your
application's public entrypoint:

```javascript
import "../vendor/datastar.js"
```

That file is owned by the application and must match its chosen client version
and license. The SDK provides the server protocol, not licensed Pro assets.
The installer currently emits a free-client CDN script; remove it when adopting
this bundled variant so two clients do not initialize the page.

The initial `data-text` node above is empty because Datastar owns its text.
For meaningful server-rendered content before JavaScript runs, render an ordinary
HEEx component and patch it by id, as in the
[complete counter example](../examples/phoenix_counter.md).
