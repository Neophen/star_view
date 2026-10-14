defmodule StarView.Dispatch do
  @moduledoc """
  Marker-based Datastar dispatch for Phoenix controllers.

  A controller is dispatchable when it uses `use StarView`, which
  injects `__star_view_handler__/0`.

  ## What this plug does

  1. Fetches object-only signals from JSON body or the Datastar query parameter.
  2. Starts the SSE response (`StarView.start/1`).
  3. Calls `handle_event/3` on the target controller.
  4. Lets `signal/3` patch browser signals immediately as your handler runs.

  This means your `handle_event/3` callbacks never need to call `StarView.start/1`
  or manually send signal patches -- just use `signal/3` and `patch_element/3`.

  Malformed signals return HTTP 400 and oversized signals return 413 before SSE
  or the handler starts. A typed `StarView.SSE.TransportError` with reason
  `:closed`, `:econnreset`, or `:epipe` halts normally; other exceptions are
  logged and re-raised. Route
  authentication and per-event authorization remain the application's job.
  """

  @behaviour Plug

  import Plug.Conn

  alias StarView.Actions
  alias StarView.Signals

  require Logger

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = fetch_query_params(conn)
    module_param = conn.path_params["module"] || conn.params["module"]
    event = conn.path_params["event"] || conn.params["event"]

    with {:ok, module} <- decode_handler(module_param),
         {:ok, signals, conn} <- Signals.fetch(conn) do
      conn
      |> StarView.start()
      |> invoke(module, event, signals, :event_first)
    else
      {:error, reason, conn} ->
        Signals.send_error(conn, reason)

      _ ->
        send_error(conn, 404, "Not found")
    end
  end

  @doc false
  def invoke(conn, module, event, signals, order) do
    apply_handler(module, event, signals, conn, order)
  rescue
    exception in StarView.SSE.TransportError ->
      transport_failure(exception, conn, module, event, __STACKTRACE__)

    exception ->
      handler_failure(exception, module, event, __STACKTRACE__)
  end

  defp apply_handler(module, event, signals, conn, :event_first),
    do: module.handle_event(event, signals, conn)

  defp apply_handler(module, event, signals, conn, :conn_first),
    do: module.handle_event(conn, event, signals)

  defp transport_failure(
         %StarView.SSE.TransportError{} = exception,
         conn,
         module,
         event,
         stacktrace
       ) do
    if StarView.SSE.TransportError.disconnected?(exception) do
      halt(exception.conn || conn)
    else
      handler_failure(exception, module, event, stacktrace)
    end
  end

  defp handler_failure(exception, module, event, stacktrace) do
    Logger.error(
      "StarView.Dispatch: #{inspect(module)}.handle_event(#{inspect(event)}) raised:\n" <>
        Exception.format(:error, exception, stacktrace)
    )

    reraise exception, stacktrace
  end

  defp decode_handler(nil), do: :error

  defp decode_handler(encoded) do
    with {:ok, module} <- Actions.decode_module(encoded),
         true <- handler?(module) do
      {:ok, module}
    else
      _ -> :error
    end
  end

  defp handler?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__star_view_handler__, 0) and
      function_exported?(module, :handle_event, 3)
  end

  defp send_error(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end
end
