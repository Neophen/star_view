defmodule StarView.Component do
  # Page/component/routing concepts adapted from dstar (MIT), Rico Trevisan, 2025.
  @moduledoc """
  Shared UI + its event handlers in one module — for drawers, pickers,
  and other components used across many pages.

      defmodule MyAppWeb.DetailDrawer do
        use StarView.Component

        def drawer(assigns) do
          ~H\"\"\"
          <div id="detail-drawer">
            <input data-on:change={event("change_title:\#{@item.id}")} />
          </div>
          \"\"\"
        end

        def handle_event("change_title:" <> _id, _signals, %{method: "POST"} = conn) do
          # ... update, then patch (SSE is already started by the dispatcher)
          patch_signals(conn, %{saved: true})
        end
      end

  Pages embed the UI as plain function components and need no
  `handle_event` clauses for it — events route to this module through
  `StarView.Dispatch`. `use StarView.Component` marks the module
  dispatchable (the same marker as `use StarView` controllers), so the
  dispatch route is the allowlist. Wire it with `StarView.Router`:

      star_view_components "/ds"

  which defaults to POST. Declare extra unsafe `:event_methods` explicitly;
  read-only GET requires a `get_events: [Module]` allowlist. A plain
  `post "/ds/:module/:event", StarView.Dispatch, [], alias: false` route
  (the installer default) also works, but only for the default POST
  events.

  Unlike `StarView.Page`, `event/2` here targets the component's dispatch
  URL: `<base>/<encoded-module>/<event>`. The base defaults to `/ds` and
  is read client-side from `<body data-ds-base="...">`, so it must match
  the base you give `star_view_components/1`. Two common setups:

      # Router: star_view_components "/ds"   (the default — no layout
      # attribute needed)

      # Custom base and/or app path prefix — declare it once in the root
      # layout, including the dispatch segment:
      #   Router: scope "/:workspace_slug" do star_view_components "/ds" end
      <Layout.app conn={@conn}
        body_attrs={%{"data-ds-base" => workspace_path(@current_scope.workspace.slug) <> "/ds"}}>
        ...
      </Layout.app>

  Colocation only: no server-side component state, no lifecycle. State
  lives in signals, the DOM, and the database.
  """

  defmacro __using__(_opts) do
    if !Code.ensure_loaded?(Phoenix.Component) do
      raise ArgumentError, """
      `use StarView.Component` requires the optional dependencies. Add to your deps:

          {:phoenix, "~> 1.7"},
          {:phoenix_live_view, "~> 1.0"}
      """
    end

    quote do
      unquote(StarView.Page.helpers())

      # Marks the module dispatchable through `StarView.Dispatch`, which
      # starts SSE before calling `handle_event/3`.
      @doc false
      def __star_view_handler__(), do: true

      @doc """
      Builds a Datastar action expression targeting this component's
      dispatch URL:
      `(document.body.dataset.dsBase || '/ds').replace(/\\/+$/, '') + '/<module>/<name>'`.

      Event names are percent-encoded literal path segments.
      `verb: :get` events bypass CSRF protection — use them only for
      side-effect-free reads.
      """
      def event(name, opts \\ []) when is_binary(name) and is_list(opts) do
        StarView.Component.build_event(__MODULE__, name, opts)
      end
    end
  end

  @doc false
  def build_event(module, name, opts)
      when is_atom(module) and is_binary(name) and is_list(opts) do
    verb = StarView.Page.Helpers.action_verb!(opts)
    path = "/" <> StarView.Actions.encode_segment!(StarView.Actions.encode_module(module))
    path = path <> "/" <> StarView.Actions.encode_segment!(name)
    base = StarView.Actions.browser_local_path("document.body.dataset.dsBase || \"/ds\"")
    args = base <> " + " <> StarView.Actions.javascript_string(path)
    StarView.Page.Helpers.action(verb, args, Keyword.get(opts, :opts))
  end
end
