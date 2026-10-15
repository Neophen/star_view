defmodule StarView.Stream.RenderState do
  @moduledoc false
  # Per-stream refresh coalescing and unchanged-patch fingerprints.
  #
  # State lives in `conn.private` and is replaced by every `StarView.Stream.run/2`,
  # so reconnects start empty. The process dictionary records which run is
  # active and its pending timer: teardown must cancel the timer after a
  # callback raises, when only the original conn is in scope, and a conn kept
  # after its run (for example in a disconnect callback) must not schedule or
  # suppress anything. Render messages carry a fresh reference; messages that
  # do not match the pending reference are stale.

  alias Plug.Conn

  @private :star_view_render
  @active_key {__MODULE__, :active_run}
  @timer_key {__MODULE__, :timer}
  @max_fingerprints 64

  defstruct run: nil,
            render?: false,
            interval: 0,
            pending: nil,
            last_at: nil,
            fingerprints: %{}

  @doc false
  def max_fingerprints(), do: @max_fingerprints

  @doc false
  def ensure_inactive!() do
    if Process.get(@active_key),
      do: raise(ArgumentError, "nested Stream.run/2 calls are not supported")
  end

  @doc false
  def init(%Conn{} = conn, render?, interval) do
    run = make_ref()
    Process.put(@active_key, run)
    state = %__MODULE__{run: run, render?: render?, interval: interval}
    Conn.put_private(conn, @private, state)
  end

  @doc false
  def invalidate(%Conn{} = conn) do
    conn |> render_state!() |> schedule(conn)
  end

  defp render_state!(conn) do
    case active_state(conn) do
      %__MODULE__{render?: true} = state -> state
      _ -> raise ArgumentError, "invalidate/1 requires a running stream with a :render callback"
    end
  end

  defp schedule(%__MODULE__{pending: nil} = state, conn) do
    token = make_ref()
    deliver(token, delay(state))
    put_state(conn, %{state | pending: token})
  end

  defp schedule(_pending_state, conn), do: conn

  defp deliver(token, 0), do: send(self(), render_message(token))

  defp deliver(token, delay) do
    Process.put(@timer_key, Process.send_after(self(), render_message(token), delay))
  end

  defp delay(%__MODULE__{last_at: nil}), do: 0
  defp delay(state), do: max(state.last_at + state.interval - now(), 0)

  @doc false
  def take(%Conn{} = conn, token) do
    take_pending(active_state(conn), conn, token)
  end

  defp take_pending(%__MODULE__{pending: token} = state, conn, token) when is_reference(token) do
    Process.delete(@timer_key)
    {:ok, put_state(conn, %{state | pending: nil, last_at: now()})}
  end

  defp take_pending(_state, _conn, _token), do: :stale

  @doc false
  def cleanup() do
    Process.delete(@active_key)
    @timer_key |> Process.delete() |> cancel_timer()
    flush_render_messages()
  end

  @doc false
  def clear(%Conn{} = conn), do: %{conn | private: Map.delete(conn.private, @private)}

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer, async: false, info: false)

  defp flush_render_messages() do
    receive do
      {:star_view_stream, :render, _token} -> flush_render_messages()
    after
      0 -> :ok
    end
  end

  @doc false
  def unchanged?(%Conn{} = conn, key, fingerprint) do
    match?(%__MODULE__{fingerprints: %{^key => ^fingerprint}}, active_state(conn))
  end

  @doc false
  def remember(%Conn{} = conn, key, fingerprint) do
    remember_in(active_state(conn), conn, key, fingerprint)
  end

  defp remember_in(%__MODULE__{} = state, conn, key, fingerprint) do
    fingerprints = put_fingerprint(state.fingerprints, key, fingerprint)
    put_state(conn, %{state | fingerprints: fingerprints})
  end

  defp remember_in(nil, conn, _key, _fingerprint), do: conn

  # Bounded: once full, new keys are not tracked, so their patches always send.
  defp put_fingerprint(fingerprints, key, fingerprint)
       when is_map_key(fingerprints, key) or map_size(fingerprints) < @max_fingerprints,
       do: Map.put(fingerprints, key, fingerprint)

  defp put_fingerprint(fingerprints, _key, _fingerprint), do: fingerprints

  @doc false
  def forget_all(%Conn{} = conn), do: forget_in(active_state(conn), conn)

  defp forget_in(%__MODULE__{fingerprints: fingerprints}, conn) when map_size(fingerprints) == 0,
    do: conn

  defp forget_in(%__MODULE__{} = state, conn), do: put_state(conn, %{state | fingerprints: %{}})
  defp forget_in(nil, conn), do: conn

  defp active_state(conn), do: active_state(conn.private[@private], Process.get(@active_key))

  defp active_state(%__MODULE__{run: run} = state, run) when is_reference(run), do: state
  defp active_state(_state, _active_run), do: nil

  defp render_message(token), do: {:star_view_stream, :render, token}
  defp put_state(conn, state), do: Conn.put_private(conn, @private, state)
  defp now(), do: System.monotonic_time(:millisecond)
end
