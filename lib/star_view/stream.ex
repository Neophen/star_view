defmodule StarView.Stream do
  @moduledoc """
  Opens an SSE stream and owns its receive loop, liveness probes, and teardown.

      case StarView.Stream.open(conn, key: current_user.id) do
        {:ok, conn} ->
          StarView.Stream.run(conn,
            connect: &subscribe/1,
            info: &handle_update/2,
            disconnect: &unsubscribe/1
          )

        {:error, conn} -> conn
      end

  Callbacks receive and return the current conn; `:info` may return
  `{:halt, conn}`. `:disconnect` runs once after a normal end, after the exact
  stream claim is released. Raises propagate after claim release. A typed
  SSE write failure with reason `:closed`, `:econnreset`, or `:epipe` ends normally.

  Probes run on a fixed deadline (`:idle_check`, default 30,000ms), even when
  application messages keep arriving. Bandit's HTTP/2 flow-control messages
  remain in the mailbox for the adapter. Generation-tagged replacement messages
  stop only their own stream, so a stale message cannot stop a newer stream on
  a reused HTTP/1.1 keep-alive process.

  Lifecycle concepts adapted from dstar (MIT), Copyright (c) 2025 Rico Trevisan.
  """

  alias Plug.Conn
  alias StarView.Signals
  alias StarView.SSE
  alias StarView.SSE.TransportError
  alias StarView.StreamRegistry

  @default_idle_check 30_000

  @doc """
  Starts SSE, optionally claiming `{key, tabId}` atomically.

  Returns `{:ok, conn}` with chunked SSE, or `{:error, conn}` with a halted
  normal HTTP response: 400/413 for invalid/oversized signals, 503 for a refused
  keyed claim. Do not subscribe on the error path. Accepts `:max_bytes` for raw
  signals. The optional registry is required only when a usable tab id and
  `:key` are both present.
  """
  @spec open(Conn.t(), keyword()) :: {:ok, Conn.t()} | {:error, Conn.t()}
  def open(%Conn{} = conn, opts \\ []) do
    conn = open_response(conn, Keyword.fetch(opts, :key), opts)
    if conn.state == :chunked, do: {:ok, conn}, else: {:error, conn}
  end

  defp open_response(conn, {:ok, key}, opts) do
    opts = opts |> Keyword.take([:max_bytes]) |> Keyword.put(:tagged, true)
    StreamRegistry.start_stream(conn, key, opts)
  end

  defp open_response(conn, :error, opts) do
    case Signals.fetch(conn, Keyword.take(opts, [:max_bytes])) do
      {:ok, _signals, conn} -> SSE.start(conn)
      {:error, reason, conn} -> Signals.send_error(conn, reason)
    end
  end

  @doc """
  Runs until a client disconnects, `:info` halts, or a newer stream takes over.

  Options: `:connect` (conn -> conn), `:info` (message, conn -> conn or
  `{:halt, conn}`), `:disconnect` (conn -> any), `:idle_check` (positive ms).
  Optional `:replaced` receives the legacy `{:EXIT, pid, :replaced}` message
  after exact claim release and before disconnect.
  """
  @spec run(Conn.t(), keyword()) :: Conn.t()
  def run(%Conn{state: :chunked} = conn, opts \\ []) do
    {conn, disconnect} = run_response(conn, opts)
    disconnect.(conn)
    conn
  end

  defp run_response(conn, opts) do
    callbacks = callbacks(opts)
    {run_connected(conn, callbacks), callbacks.disconnect}
  after
    StreamRegistry.release(conn)
  end

  defp run_connected(conn, callbacks) do
    conn |> callbacks.connect.() |> ensure_conn!() |> loop(callbacks, deadline(callbacks))
  rescue
    exception in TransportError -> transport_failure(exception, conn, callbacks, __STACKTRACE__)
  end

  defp callbacks(opts) do
    %{
      connect: Keyword.get(opts, :connect, & &1),
      info: Keyword.get(opts, :info, fn _message, conn -> conn end),
      replaced: Keyword.get(opts, :replaced, fn _message, conn -> conn end),
      disconnect: Keyword.get(opts, :disconnect, fn _conn -> :ok end),
      idle_check: idle_check!(Keyword.get(opts, :idle_check, @default_idle_check))
    }
  end

  defp idle_check!(value) when is_integer(value) and value > 0, do: value
  defp idle_check!(_value), do: raise(ArgumentError, ":idle_check must be a positive integer")

  defp transport_failure(%TransportError{} = exception, conn, callbacks, stacktrace) do
    if TransportError.disconnected?(exception) do
      teardown(exception.conn || conn, callbacks)
    else
      reraise exception, stacktrace
    end
  end

  defp loop(conn, callbacks, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0,
      do: probe(conn, callbacks),
      else: receive_one(conn, callbacks, deadline, remaining)
  end

  defp probe(conn, callbacks) do
    case Conn.chunk(conn, ": \n\n") do
      {:ok, conn} -> loop(conn, callbacks, deadline(callbacks))
      {:error, reason} -> raise TransportError, reason: reason, conn: conn
    end
  end

  defp receive_one(conn, callbacks, deadline, remaining) do
    receive do
      {:plug_conn, :sent} ->
        loop(conn, callbacks, deadline)

      {:EXIT, _pid, :normal} ->
        loop(conn, callbacks, deadline)

      {:EXIT, _pid, :replaced} ->
        loop(conn, callbacks, deadline)

      {:EXIT, _pid, {:replaced, _token}} = message ->
        replacement(conn, callbacks, deadline, message)

      {:star_view_stream, :replaced, _pid, _token} = message ->
        replacement(conn, callbacks, deadline, message)

      {:EXIT, _pid, reason} ->
        exit(reason)

      message
      when not is_tuple(message) or tuple_size(message) != 2 or elem(message, 0) != :bandit ->
        message |> callbacks.info.(conn) |> continue(callbacks, deadline)
    after
      remaining -> probe(conn, callbacks)
    end
  end

  defp replacement(conn, callbacks, deadline, message) do
    if StreamRegistry.replacement_for?(conn, message) do
      end_replaced(conn, callbacks, message)
    else
      loop(conn, callbacks, deadline)
    end
  end

  defp end_replaced(conn, callbacks, message) do
    StreamRegistry.release(conn)

    message
    |> StreamRegistry.public_replacement()
    |> callbacks.replaced.(conn)
    |> unwrap_halt()
    |> teardown(callbacks)
  end

  defp continue({:halt, conn}, callbacks, _deadline),
    do: conn |> ensure_conn!() |> teardown(callbacks)

  defp continue(conn, callbacks, deadline),
    do: conn |> ensure_conn!() |> loop(callbacks, deadline)

  defp unwrap_halt({:halt, conn}), do: ensure_conn!(conn)
  defp unwrap_halt(conn), do: ensure_conn!(conn)

  defp ensure_conn!(%Conn{} = conn), do: conn

  defp ensure_conn!(other),
    do: raise(ArgumentError, "stream callback must return a conn, got: #{inspect(other)}")

  defp teardown(conn, _callbacks) do
    StreamRegistry.release(conn)
    conn
  end

  defp deadline(callbacks), do: System.monotonic_time(:millisecond) + callbacks.idle_check
end
