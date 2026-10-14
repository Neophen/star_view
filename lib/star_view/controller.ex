defmodule StarView.Controller do
  @moduledoc """
  Phoenix controller helpers for StarView.

  Use `use StarView` from your web module after
  `use Phoenix.Controller` has been applied:

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

  Controllers implement `StarView`:

      @impl StarView
      def handle_event("increment", signals, conn), do: ...

  ## `assign/3` vs `signal/3`

  - `assign/3` sets a Plug connection assign. Function components can read it
    via `@key`, but it is never sent to the browser.
  - `signal/3` does `assign/3` and sends the value to the browser when the
    connection is already an SSE response. Before SSE starts, it records the
    value for `init_signals/1`.
  """

  import Plug.Conn

  @signals_key :star_view_signals_keys_and_opts

  defmacro __using__(opts \\ []) do
    auto_render? = Keyword.get(opts, :auto_render, true)

    quote bind_quoted: [auto_render?: auto_render?] do
      @behaviour StarView

      import StarView.Controller

      @doc false
      def __star_view_handler__(), do: true

      def render_html(conn) do
        conn
        |> Phoenix.Controller.put_view(html: __MODULE__)
        |> Phoenix.Controller.render(:render)
      end

      def get(name_or_opts \\ []), do: StarView.Actions.get(__MODULE__, name_or_opts)
      def get(event_name, opts), do: StarView.Actions.get(__MODULE__, event_name, opts)

      def post(name_or_opts \\ []), do: StarView.Actions.post(__MODULE__, name_or_opts)
      def post(event_name, opts), do: StarView.Actions.post(__MODULE__, event_name, opts)

      def put(name_or_opts \\ []), do: StarView.Actions.put(__MODULE__, name_or_opts)
      def put(event_name, opts), do: StarView.Actions.put(__MODULE__, event_name, opts)

      def patch(name_or_opts \\ []), do: StarView.Actions.patch(__MODULE__, name_or_opts)
      def patch(event_name, opts), do: StarView.Actions.patch(__MODULE__, event_name, opts)

      def delete(name_or_opts \\ []), do: StarView.Actions.delete(__MODULE__, name_or_opts)
      def delete(event_name, opts), do: StarView.Actions.delete(__MODULE__, event_name, opts)

      if auto_render? do
        def action(conn, opts) do
          conn = super(conn, opts)
          StarView.Controller.__maybe_auto_render__(__MODULE__, conn)
        end

        defoverridable action: 2
      end

      defoverridable render_html: 1
    end
  end

  @doc """
  Assigns a value and exposes it as a Datastar signal.

  Before the SSE response starts, the signal is recorded for `init_signals/1`.
  During an SSE response, the signal is patched immediately so the browser sees
  updates in the same order as the server pipeline.
  """
  @spec signal(Plug.Conn.t(), atom(), term(), keyword()) :: Plug.Conn.t()
  def signal(%Plug.Conn{} = conn, key, value, opts \\ []) when is_atom(key) do
    conn
    |> assign(key, value)
    |> put_or_patch_signal(key, value, opts)
  end

  @doc """
  Patches a rendered component or HTML value against current assigns.
  """
  @spec patch_element(Plug.Conn.t(), (map() -> term()) | term(), keyword()) :: Plug.Conn.t()
  def patch_element(%Plug.Conn{} = conn, component_or_html, opts \\ []) do
    opts =
      case Keyword.pop(opts, :to) do
        {nil, opts} -> opts
        {to, opts} -> Keyword.put(opts, :selector, dom_id(to))
      end

    html =
      if is_function(component_or_html, 1) do
        component_or_html.(Map.put_new(conn.assigns, :__changed__, nil))
      else
        component_or_html
      end

    StarView.patch_elements(conn, html, opts)
  end

  @doc """
  Flushes tracked pre-start signals as Datastar signal patch events.

  This is retained for manual flows that call `signal/4` before starting SSE.
  Controllers dispatched through `StarView.Dispatch` patch signals immediately
  and do not need a final flush.
  """
  @spec flush_signals(Plug.Conn.t()) :: Plug.Conn.t()
  def flush_signals(%Plug.Conn{} = conn) do
    case extract_signals(conn) do
      [] ->
        conn

      signals ->
        Enum.reduce(signals, conn, fn {key, value, opts}, conn ->
          StarView.patch_signals(conn, %{key => value}, opts)
        end)
    end
  end

  @doc """
  Returns the tracked signal map as JSON for `data-signals`.
  """
  @spec init_signals(Plug.Conn.t()) :: String.t() | nil
  def init_signals(%Plug.Conn{} = conn) do
    case extract_signals(conn) do
      [] ->
        nil

      signals ->
        signals
        |> Map.new(fn {key, value, _opts} -> {key, value} end)
        |> StarView.JSON.encode!()
    end
  end

  @doc """
  Extracts tracked signal keys, values, and per-signal options.
  """
  @spec extract_signals(Plug.Conn.t()) :: [{atom(), term(), keyword()}]
  def extract_signals(%Plug.Conn{} = conn) do
    conn.private
    |> Map.get(@signals_key, [])
    |> Enum.reverse()
    |> Enum.map(fn {key, opts} -> {key, conn.assigns[key], opts} end)
  end

  @doc false
  def __maybe_auto_render__(module, %Plug.Conn{state: :unset, halted: false} = conn) do
    if function_exported?(module, :render, 1) do
      conn
      |> then(&apply(:"Elixir.Phoenix.Controller", :put_view, [&1, [html: module]]))
      |> then(&apply(:"Elixir.Phoenix.Controller", :render, [&1, :render]))
    else
      conn
    end
  end

  def __maybe_auto_render__(_module, conn), do: conn

  @doc false
  def dom_id("#" <> _ = id), do: id
  def dom_id(id) when is_binary(id), do: "#" <> id

  defp put_or_patch_signal(%Plug.Conn{} = conn, key, value, opts) do
    if sse_started?(conn) do
      StarView.patch_signals(conn, %{key => value}, opts)
    else
      put_signal_key(conn, key, opts)
    end
  end

  defp sse_started?(%Plug.Conn{state: :chunked}), do: true
  defp sse_started?(%Plug.Conn{}), do: false

  defp put_signal_key(%Plug.Conn{} = conn, key, opts) do
    put_private(conn, @signals_key, [{key, opts} | Map.get(conn.private, @signals_key, [])])
  end
end
