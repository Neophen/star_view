defmodule StarView.Page do
  # Page/component/routing concepts adapted from dstar (MIT), Rico Trevisan, 2025.
  @moduledoc """
  One module per page: render, event handlers, stream callbacks, and
  colocated function components.

      defmodule MyAppWeb.CounterPage do
        use StarView.Page

        alias MyAppWeb.Components.StarView.Layout

        def mount(conn, _params), do: assign(conn, count: 0)

        def render(assigns) do
          ~H\"\"\"
          <Layout.app conn={@conn}>
            <div data-signals:count={@count}>
              <button data-on:click={event("increment")}>+1</button>
            </div>
          </Layout.app>
          \"\"\"
        end

        def handle_event("increment", %{"count" => count}, %{method: "POST"} = conn)
            when is_integer(count) and count >= 0 and count < 1_000_000 do
          patch_signals(conn, %{count: count + 1})
        end

        def handle_event(_event, _signals, conn), do: conn
      end

  Route it with `StarView.Router.star_view/2`:

      import StarView.Router
      star_view "/counter", MyAppWeb.CounterPage

  `StarView.Page.Plug` owns the HTTP and stream lifecycle; pages implement
  application callbacks. Conn in, conn out.

  ## Layout

  `StarView.Page.Plug` disables the Phoenix root layout before `mount/2`,
  because the generated `Components.StarView.Layout` owns the document
  (Datastar script, CSRF signal, initial signals) — render through
  `Layout.app/1`. To render inside your Phoenix root layout instead, put it
  back in `mount/2`:

      def mount(conn, _params) do
        Phoenix.Controller.put_root_layout(conn, html: {MyAppWeb.Layouts, :root})
      end

  ## Options

  - `:idle_check` — ms between connection liveness checks in the stream
    loop (default `30_000`).
  - `:refresh_interval` — minimum ms between `handle_refresh/1` calls
    (default `0`).

  ## Coalesced refresh

  Define `handle_refresh/1` to re-render after scoped invalidations. It runs
  once after `handle_connect/2` (so the stream starts from a current snapshot
  after load or reconnect) and once per burst of `StarView.invalidate/1` calls:

      def handle_connect(conn, _params) do
        Phoenix.PubSub.subscribe(MyApp.PubSub, "orders:" <> conn.assigns.current_scope.org_id)
        conn
      end

      def handle_info({:order_changed, _id}, conn), do: StarView.invalidate(conn)

      def handle_refresh(conn) do
        orders = MyApp.Orders.list_for(conn.assigns.current_scope)
        patch(conn, &orders/1, [orders: orders], key: :orders, only_changed: true)
      end

  Read and authorize business state inside the callback from trusted conn
  assigns; it may return `{:halt, conn}`. See `StarView.Stream`.
  `StarView.invalidate/1` is called qualified rather than imported, so pages
  that already define their own `invalidate/1` keep compiling.
  """

  @doc "GET: load data and assign what `render/1` needs. Optional."
  @callback mount(Plug.Conn.t(), params :: map()) :: Plug.Conn.t()

  @doc "The full-page HEEx template. Required."
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc "Handles a Datastar event request. SSE is already started. Optional."
  @callback handle_event(event :: String.t(), signals :: map(), Plug.Conn.t()) :: Plug.Conn.t()

  @doc """
  Stream open: subscribe to topics, assign loop state. Optional —
  defining it enables `POST /path` streaming.
  """
  @callback handle_connect(Plug.Conn.t(), params :: map()) :: Plug.Conn.t()

  @doc "Handles one message from the library-owned receive loop. Optional."
  @callback handle_info(msg :: term(), Plug.Conn.t()) :: Plug.Conn.t() | {:halt, Plug.Conn.t()}

  @doc "If defined, the stream opens via `StarView.Stream.open/2` keyed on the result. Optional."
  @callback stream_key(Plug.Conn.t()) :: term()

  @doc "Runs once after stream claim release, including exceptions. Receives the latest completed callback conn."
  @callback handle_disconnect(Plug.Conn.t()) :: term()

  @doc """
  Renders current state after `handle_connect/2` and after coalesced
  `StarView.invalidate/1` calls. Optional — defining it enables refresh for the stream.
  """
  @callback handle_refresh(Plug.Conn.t()) :: Plug.Conn.t() | {:halt, Plug.Conn.t()}

  @optional_callbacks mount: 2,
                      handle_event: 3,
                      handle_connect: 2,
                      handle_info: 2,
                      handle_disconnect: 1,
                      handle_refresh: 1,
                      stream_key: 1

  @default_idle_check 30_000
  @default_refresh_interval 0

  defmacro __using__(opts) do
    if !Code.ensure_loaded?(Phoenix.Component) do
      raise ArgumentError, """
      `use StarView.Page` requires the optional dependencies. Add to your deps:

          {:phoenix, "~> 1.7"},
          {:phoenix_live_view, "~> 1.0"}
      """
    end

    idle_check = idle_check!(Keyword.get(opts, :idle_check, @default_idle_check))

    refresh_interval =
      refresh_interval!(Keyword.get(opts, :refresh_interval, @default_refresh_interval))

    quote do
      @behaviour StarView.Page

      unquote(helpers(event: 1, event: 2, connect: 0, connect: 1, patch: 3, patch: 4))
      @doc false
      def __star_view__(:idle_check), do: unquote(idle_check)
      def __star_view__(:refresh_interval), do: unquote(refresh_interval)
    end
  end

  defp idle_check!(value) when is_integer(value) and value > 0, do: value
  defp idle_check!(_value), do: raise(ArgumentError, ":idle_check must be a positive integer")

  defp refresh_interval!(value) when is_integer(value) and value >= 0, do: value

  defp refresh_interval!(_value),
    do: raise(ArgumentError, ":refresh_interval must be a non-negative integer")

  @doc false
  def helpers(imports \\ [patch: 3, patch: 4]) do
    quote do
      use Phoenix.Component

      # Re-importing overrides the import set from `use Phoenix.Component`,
      # freeing the assign family for the conn/component shim below.
      import Phoenix.Component,
        except: [assign: 2, assign: 3, assign_new: 3, update: 3]

      import StarView,
        only: [
          start: 1,
          start_stream: 2,
          check_connection: 1,
          read_signals: 1,
          read_signals!: 1,
          patch_signals: 2,
          patch_signals: 3,
          remove_signals: 2,
          remove_signals: 3,
          patch_elements: 2,
          patch_elements: 3,
          remove_elements: 2,
          remove_elements: 3,
          execute_script: 2,
          execute_script: 3,
          redirect: 2,
          redirect: 3,
          console_log: 2,
          console_log: 3
        ]

      import StarView.Page.Assigns
      import StarView.Page.Helpers, only: unquote(imports)
    end
  end
end
