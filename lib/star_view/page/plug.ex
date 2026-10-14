if Code.ensure_loaded?(Phoenix.Controller) do
  defmodule StarView.Page.Plug do
    @moduledoc """
    Drives explicitly routed `StarView.Page` callbacks.

    GET mounts and renders the page. Events fetch bounded object signals before
    SSE and use the shared dispatcher. POST streaming uses `StarView.Stream`'s
    fixed-deadline probes and generation-aware ownership.

    Authentication belongs in the route pipeline; every event must authorize its
    own operation. Mount is not called for events or stream connections.
    `handle_disconnect/1`, when defined, runs once after stream claim release,
    including raised callbacks. It receives the latest completed callback conn.

    Set `config :star_view, debug_errors: true` in development to relay event
    exceptions to the browser console. Production should leave this disabled.
    """

    @behaviour Plug

    alias Plug.Conn
    alias StarView.Dispatch
    alias StarView.Signals
    alias StarView.SSE.TransportError
    alias StarView.Stream

    require Logger

    @impl Plug
    def init({action, page}) when action in [:page, :event, :stream] and is_atom(page),
      do: {action, page}

    @impl Plug
    def call(conn, {:page, page}), do: page(conn, page)
    def call(conn, {:event, page}), do: event(conn, page)
    def call(conn, {:stream, page}), do: stream(conn, page)

    defp page(conn, page) do
      conn =
        conn
        |> Conn.fetch_query_params()
        |> ensure_html_format()
        |> Phoenix.Controller.put_root_layout(html: false)
        |> mount(page)

      render_page(conn, page)
    end

    defp mount(conn, page) do
      if exported?(page, :mount, 2), do: page.mount(conn, conn.params), else: conn
    end

    defp render_page(%Conn{halted: true} = conn, _page), do: conn
    defp render_page(%Conn{state: state} = conn, _page) when state != :unset, do: conn

    defp render_page(conn, page) do
      conn |> Phoenix.Controller.put_view(html: page) |> Phoenix.Controller.render(:render)
    end

    defp ensure_html_format(conn) do
      if Phoenix.Controller.get_format(conn),
        do: conn,
        else: Phoenix.Controller.put_format(conn, "html")
    end

    defp event(conn, page) do
      if exported?(page, :handle_event, 3), do: fetch_event(conn, page), else: not_found(conn)
    end

    defp fetch_event(conn, page) do
      conn = Conn.fetch_query_params(conn)
      event = Map.fetch!(conn.path_params, "event")

      case Signals.fetch(conn) do
        {:ok, signals, conn} -> invoke_event(StarView.SSE.start(conn), page, event, signals)
        {:error, reason, conn} -> Signals.send_error(conn, reason)
      end
    end

    defp invoke_event(conn, page, event, signals) do
      Dispatch.invoke(conn, page, event, signals, :event_first)
    rescue
      exception ->
        relay_debug_error(conn, exception, __STACKTRACE__)
        reraise exception, __STACKTRACE__
    end

    defp relay_debug_error(conn, exception, stacktrace) do
      if Application.get_env(:star_view, :debug_errors, false),
        do: send_debug_error(conn, exception, stacktrace)
    end

    defp send_debug_error(conn, exception, stacktrace) do
      StarView.console_log(conn, Exception.format(:error, exception, stacktrace), level: :error)
    rescue
      _ -> :ok
    end

    defp stream(conn, page) do
      if exported?(page, :handle_connect, 2), do: open_stream(conn, page), else: not_found(conn)
    end

    defp open_stream(conn, page) do
      conn = Conn.fetch_query_params(conn)

      case Stream.open(conn, stream_options(conn, page)) do
        {:ok, conn} -> run_stream(conn, page)
        {:error, conn} -> conn
      end
    end

    defp stream_options(conn, page) do
      if exported?(page, :stream_key, 1), do: [key: page.stream_key(conn)], else: []
    end

    defp run_stream(conn, page) do
      key = {__MODULE__, make_ref()}
      Process.put(key, conn)
      run_lifecycle(conn, page, key)
    end

    defp run_lifecycle(conn, page, key) do
      outcome = stream_outcome(conn, page, key)
      conn = Process.delete(key)
      complete(outcome, page, conn)
    end

    defp stream_outcome(conn, page, key) do
      result =
        Stream.run(conn,
          connect: &connect(&1, page, key),
          info: &info(&1, &2, page, key),
          idle_check: page.__star_view__(:idle_check)
        )

      {:ok, result}
    rescue
      exception -> {:raised, :error, exception, __STACKTRACE__}
    catch
      kind, reason -> {:raised, kind, reason, __STACKTRACE__}
    end

    defp complete({:ok, result}, page, conn) do
      disconnect(page, conn)
      result
    end

    defp complete({:raised, kind, reason, stacktrace}, page, conn) do
      cleanup_preserving_error(page, conn)
      :erlang.raise(kind, reason, stacktrace)
    end

    defp cleanup_preserving_error(page, conn) do
      disconnect(page, conn)
    rescue
      exception -> log_cleanup_error(page, :error, exception, __STACKTRACE__)
    catch
      kind, reason -> log_cleanup_error(page, kind, reason, __STACKTRACE__)
    end

    defp log_cleanup_error(page, kind, reason, stacktrace) do
      Logger.error(
        "#{inspect(page)}.handle_disconnect failed during callback error cleanup:\n" <>
          Exception.format(kind, reason, stacktrace)
      )
    end

    defp connect(conn, page, key) do
      page |> invoke(:handle_connect, [conn, conn.params]) |> remember(key)
    end

    defp info(message, conn, page, key) do
      page |> dispatch_info(message, conn) |> remember(key)
    end

    defp remember(%Conn{} = conn, key) do
      Process.put(key, conn)
      conn
    end

    defp remember({:halt, %Conn{} = conn} = result, key) do
      Process.put(key, conn)
      result
    end

    defp remember(result, _key), do: result

    defp disconnect(page, conn) do
      if exported?(page, :handle_disconnect, 1), do: invoke(page, :handle_disconnect, [conn])
    end

    defp dispatch_info(page, message, conn) do
      if exported?(page, :handle_info, 2), do: handle_info(page, message, conn), else: conn
    end

    defp handle_info(page, message, conn) do
      page.handle_info(message, conn)
    rescue
      exception in FunctionClauseError ->
        handle_unmatched(exception, page, message, conn, __STACKTRACE__)

      exception ->
        callback_failure(exception, page, :handle_info, __STACKTRACE__)
    end

    defp handle_unmatched(exception, page, message, conn, stacktrace) do
      if callback_head_error?(exception, page, message, conn, stacktrace) do
        Logger.warning("#{inspect(page)} received unhandled message: #{inspect(message)}")
        conn
      else
        callback_failure(exception, page, :handle_info, stacktrace)
      end
    end

    defp callback_head_error?(
           %FunctionClauseError{module: page, function: :handle_info, arity: 2},
           page,
           message,
           conn,
           [{page, :handle_info, [message, conn], _location} | _rest]
         ), do: true

    defp callback_head_error?(_error, _page, _message, _conn, _stacktrace), do: false

    defp invoke(page, callback, arguments) do
      apply(page, callback, arguments)
    rescue
      exception -> callback_failure(exception, page, callback, __STACKTRACE__)
    end

    defp callback_failure(%TransportError{} = exception, page, callback, stacktrace) do
      if TransportError.disconnected?(exception),
        do: reraise(exception, stacktrace),
        else: log_and_raise(exception, page, callback, stacktrace)
    end

    defp callback_failure(exception, page, callback, stacktrace),
      do: log_and_raise(exception, page, callback, stacktrace)

    defp log_and_raise(exception, page, callback, stacktrace) do
      Logger.error(
        "StarView.Page.Plug: #{inspect(page)}.#{callback} raised:\n" <>
          Exception.format(:error, exception, stacktrace)
      )

      reraise exception, stacktrace
    end

    defp exported?(module, function, arity),
      do: Code.ensure_loaded?(module) and function_exported?(module, function, arity)

    defp not_found(conn), do: conn |> Conn.send_resp(404, "Not found") |> Conn.halt()
  end
end
