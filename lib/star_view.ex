defmodule StarView do
  @moduledoc """
  Elixir SDK helpers for Datastar.

  The facade functions in this module delegate to small protocol modules while
  keeping a pipeline-friendly Plug API:

      conn
      |> StarView.start()
      |> StarView.patch_signals(%{count: 1})
      |> StarView.patch_elements(~s(<div id="count">1</div>))

  ## Controller Behaviour

  Use `use StarView` in your `AppWeb.star_view/0` macro, then
  implement callbacks with `@impl StarView`:

  ### Lifecycle

  1. `mount/2` — Sets up initial signals and assigns for the page load.
  2. `render/1` — Renders the HEEx template. The generated `Layout.app/1`
     wrapper uses `init_signals/1` to emit the `data-signals` attribute for
     the initial client state.
  3. `handle_event/3` — Called by `StarView.Dispatch` when a Datastar
     action fires. The dispatcher starts the SSE response before this callback,
     so `signal/3` patches browser signals immediately.

  ### Example

      @impl StarView
      def mount(conn, _params) do
        conn
        |> signal(:count, 0)
        |> signal(:step, 1)
      end

      @impl StarView
      def render(assigns) do
        ~H\"""
        <Layout.app conn={@conn}>
          <button data-on:click={post("increment")}>+</button>
          <span data-text="$count">{@count}</span>
        </Layout.app>
        \"""
      end

      @impl StarView
      def handle_event("increment", signals, conn) do
        conn
        |> signal(:count, Map.get(signals, "count", 0) + 1)
      end
  """

  @callback mount(Plug.Conn.t(), map()) :: Plug.Conn.t()
  @callback render(map()) :: term()
  @callback handle_event(String.t(), map(), Plug.Conn.t()) :: Plug.Conn.t()

  @optional_callbacks handle_event: 3

  @doc """
  Provides Phoenix controller helpers.

  Use `use StarView` in your `AppWeb.star_view/0` macro
  instead of `use StarView.Controller` directly:

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
  """
  defmacro __using__(opts \\ []) do
    quote do
      use StarView.Controller, unquote(opts)
    end
  end

  @doc """
  Starts a Server-Sent Events response on a Plug connection.
  """
  @spec start(Plug.Conn.t()) :: Plug.Conn.t()
  defdelegate start(conn), to: StarView.SSE

  @doc """
  Sends a raw Datastar SSE event and returns the updated connection.
  """
  @spec send(Plug.Conn.t(), String.t(), [String.t()] | String.t(), keyword()) :: Plug.Conn.t()
  defdelegate send(conn, event_type, data_lines, opts \\ []),
    to: StarView.SSE,
    as: :send!

  @doc """
  Starts an SSE stream with per-tab deduplication.

  Requires `StarView.StreamRegistry` in your supervision tree
  and a `tabId` signal in your root layout. See
  `StarView.StreamRegistry` for setup.
  """
  @spec start_stream(Plug.Conn.t(), term()) :: Plug.Conn.t()
  defdelegate start_stream(conn, scope_key), to: StarView.StreamRegistry

  @doc "Starts a keyed SSE stream with configurable signal input options."
  defdelegate start_stream(conn, scope_key, opts), to: StarView.StreamRegistry

  @doc """
  Requests one coalesced `:render` from the running stream; see `StarView.Stream.invalidate/1`.
  """
  @spec invalidate(Plug.Conn.t()) :: Plug.Conn.t()
  defdelegate invalidate(conn), to: StarView.Stream

  @doc """
  Checks whether a chunked SSE connection still accepts writes.
  """
  @spec check_connection(Plug.Conn.t()) :: {:ok, Plug.Conn.t()} | {:error, Plug.Conn.t()}
  defdelegate check_connection(conn), to: StarView.SSE

  @doc "Fetches object signals and returns Plug's updated conn; see `StarView.Signals.fetch/2`."
  defdelegate fetch_signals(conn, opts \\ []), to: StarView.Signals, as: :fetch

  @doc """
  Reads Datastar signals from a Plug connection.

  Returns a signal map. Raises `StarView.Signals.ReadError` when the
  payload cannot be decoded. Plugs that need `{:ok, map()} | {:error, term()}`
  should call `StarView.Signals.read/1` instead.
  """
  @spec read_signals(Plug.Conn.t()) :: map()
  def read_signals(conn), do: StarView.Signals.read!(conn)

  @doc """
  Reads Datastar signals from a Plug connection, raising on invalid JSON.
  """
  @spec read_signals!(Plug.Conn.t()) :: map()
  defdelegate read_signals!(conn), to: StarView.Signals, as: :read!

  @doc """
  Patches one or more complete HTML elements into the DOM.
  """
  @spec patch_elements(Plug.Conn.t(), iodata() | tuple() | nil, keyword()) :: Plug.Conn.t()
  defdelegate patch_elements(conn, elements, opts \\ []), to: StarView.Elements, as: :patch

  @doc """
  Removes elements from the DOM by CSS selector.
  """
  @spec remove_elements(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defdelegate remove_elements(conn, selector, opts \\ []), to: StarView.Elements, as: :remove

  @doc """
  Patches client-side Datastar signals using RFC 7386 JSON Merge Patch semantics.
  """
  @spec patch_signals(Plug.Conn.t(), map(), keyword()) :: Plug.Conn.t()
  defdelegate patch_signals(conn, signals, opts \\ []), to: StarView.Signals, as: :patch

  @doc """
  Patches client-side Datastar signals from a pre-encoded JSON string.
  """
  @spec patch_signals_raw(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defdelegate patch_signals_raw(conn, signals_json, opts \\ []),
    to: StarView.Signals,
    as: :patch_raw

  @doc """
  Removes signals by setting one or more dot-notated signal paths to `null`.
  """
  @spec remove_signals(Plug.Conn.t(), String.t() | [String.t()], keyword()) :: Plug.Conn.t()
  defdelegate remove_signals(conn, paths, opts \\ []), to: StarView.Signals

  @doc """
  Executes JavaScript in the browser by appending a script element.
  """
  @spec execute_script(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defdelegate execute_script(conn, script, opts \\ []), to: StarView.Scripts, as: :execute

  @doc """
  Redirects the browser by executing a tiny client-side script.
  """
  @spec redirect(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  defdelegate redirect(conn, url, opts \\ []), to: StarView.Scripts

  @doc """
  Logs a value to the browser console.
  """
  @spec console_log(Plug.Conn.t(), term(), keyword()) :: Plug.Conn.t()
  defdelegate console_log(conn, message, opts \\ []), to: StarView.Scripts
end
