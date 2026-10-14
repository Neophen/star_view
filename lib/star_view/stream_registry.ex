defmodule StarView.StreamRegistry do
  @moduledoc """
  Opt-in per-tab stream ownership with atomic claims and bounded handover.

  Add `StarView.StreamRegistry` to the supervision tree. Each `{scope_key,
  tabId}` has one active owner. A new claim retires the previous generation,
  signals it to stop, and escalates only if that generation has not released
  within `:grace_ms` (default 1,000ms).

  Put the per-tab signal in the root layout:

      <body data-signals:tab-id="sessionStorage.getItem('_sv_tab') || (() => { const id = crypto.randomUUID(); sessionStorage.setItem('_sv_tab', id); return id; })()">

  Prefer `StarView.Stream.open/2` and `StarView.Stream.run/2`, which release the
  exact claim on teardown and ignore stale takeover messages on HTTP/1.1
  keep-alive processes. Manual streams must call `release/1` when they finish.
  `start_stream/2` retains the legacy `:replaced` exit reason; `StarView.Stream`
  opts into generation-tagged replacement messages.

  Adapted from [dstar](https://github.com/ricotrevisan/dstar) (MIT),
  Copyright (c) 2025 Rico Trevisan.
  """

  use GenServer

  alias Plug.Conn
  alias StarView.Signals

  @claim_private :star_view_stream_claim
  @default_grace_ms 1_000
  @max_tab_id_bytes 256

  @doc false
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  def init(opts) do
    grace_ms = Keyword.get(opts, :grace_ms, @default_grace_ms)

    if not is_integer(grace_ms) or grace_ms <= 0 do
      raise ArgumentError, ":grace_ms must be a positive integer"
    end

    {:ok, %{active: %{}, claims: %{}, monitors: %{}, grace_ms: grace_ms}}
  end

  @doc """
  Starts SSE, atomically claiming `{scope_key, tabId}` when a usable tab id is
  present. Malformed signals return halted HTTP 400, oversized signals 413,
  and an unavailable coordinator 503, before SSE starts. Missing or invalid
  tab ids retain the unkeyed fallback. Accepts `:max_bytes` for raw signals.
  """
  @spec start_stream(Conn.t(), term(), keyword()) :: Conn.t()
  def start_stream(conn, scope_key, opts \\ []) do
    case Signals.fetch(conn, Keyword.take(opts, [:max_bytes])) do
      {:ok, signals, conn} -> start_fetched(conn, scope_key, tab_id(signals), opts)
      {:error, reason, conn} -> Signals.send_error(conn, reason)
    end
  end

  defp start_fetched(conn, _scope_key, nil, _opts), do: StarView.start(conn)

  defp start_fetched(conn, scope_key, tab_id, opts) do
    key = {scope_key, tab_id}

    case coordinator_call({:claim, key, Keyword.get(opts, :tagged, false)}) do
      {:ok, token} -> start_claimed(conn, key, token)
      {:error, _reason} -> claim_error(conn)
    end
  end

  defp start_claimed(conn, key, token) do
    conn = Conn.put_private(conn, @claim_private, %{key: key, token: token})

    try do
      StarView.start(conn)
    catch
      kind, reason ->
        release(conn)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp claim_error(conn) do
    conn
    |> Conn.put_resp_content_type("text/plain")
    |> Conn.send_resp(503, "Stream registry unavailable")
    |> Conn.halt()
  end

  @doc """
  Atomically claims a manual stream key. Returns `:ok` only when the caller
  became active owner; coordinator failures return `{:error, reason}`.
  Manual callers retain the legacy `:replaced` exit reason and must call
  `unregister_self/0` before reusing their request process.
  """
  @spec replace_and_register(term()) :: :ok | {:error, term()}
  def replace_and_register(key) do
    case coordinator_call({:claim, key, false}) do
      {:ok, _token} -> :ok
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Synchronously releases the exact claim stored in `conn`. A stale conn cannot
  release a newer generation. Once this returns, the released generation's
  escalation cannot kill a reused keep-alive process. Unkeyed conns are a no-op.
  """
  @spec release(Conn.t()) :: :ok
  def release(%Conn{} = conn) do
    case conn.private[@claim_private] do
      %{token: token} -> release_token(token)
      _ -> :ok
    end
  end

  defp release_token(token) do
    _ = coordinator_call({:release, token})
    :ok
  end

  @doc "Releases a stream's claim and returns the conn for manual pipelines."
  def unregister_stream(%Conn{} = conn) do
    release(conn)
    conn
  end

  @doc "Synchronously releases all claims owned by the calling process."
  @spec unregister_self() :: :ok
  def unregister_self() do
    _ = coordinator_call(:release_self)
    :ok
  end

  @doc "Returns the active owner and its generation, or `:error` when absent."
  @spec owner(term()) :: {:ok, pid(), reference()} | :error
  def owner(key) do
    case coordinator_call({:owner, key}) do
      {:error, _reason} -> :error
      result -> result
    end
  end

  @doc false
  def replacement_for?(%Conn{} = conn, {:EXIT, _pid, {:replaced, token}}) do
    match?(%{token: ^token}, conn.private[@claim_private])
  end

  def replacement_for?(%Conn{} = conn, {:star_view_stream, :replaced, _pid, token}) do
    match?(%{token: ^token}, conn.private[@claim_private])
  end

  def replacement_for?(%Conn{}, _message), do: false

  @doc false
  def public_replacement({:EXIT, pid, {:replaced, _token}}), do: {:EXIT, pid, :replaced}
  def public_replacement({:star_view_stream, :replaced, pid, _token}), do: {:EXIT, pid, :replaced}

  defp tab_id(signals) do
    signals |> Map.get("tabId") |> usable_tab_id()
  end

  defp usable_tab_id(tab_id)
       when is_binary(tab_id) and byte_size(tab_id) in 1..@max_tab_id_bytes do
    if String.valid?(tab_id) and String.trim(tab_id) != "", do: tab_id
  end

  defp usable_tab_id(_tab_id), do: nil

  defp coordinator_call(request) do
    GenServer.call(__MODULE__, request, :infinity)
  catch
    :exit, reason -> {:error, {:registry_exit, reason}}
  end

  @impl GenServer
  def handle_call({:claim, key, tagged?}, {pid, _tag}, state) do
    claim(key, pid, tagged?, active_claim(state, key), state)
  end

  def handle_call({:release, token}, {pid, _tag}, state) do
    {:reply, :ok, release_owned(state, token, pid)}
  end

  def handle_call(:release_self, {pid, _tag}, state) do
    tokens = for {token, %{pid: ^pid}} <- state.claims, do: token
    {:reply, :ok, Enum.reduce(tokens, state, &drop_claim(&2, &1))}
  end

  def handle_call({:owner, key}, _from, state) do
    {:reply, owner_result(active_claim(state, key)), state}
  end

  defp owner_result(nil), do: :error
  defp owner_result(%{pid: pid, token: token}), do: {:ok, pid, token}

  defp claim(_key, pid, _tagged?, %{pid: pid, token: token}, state) do
    {:reply, {:ok, token}, state}
  end

  defp claim(key, pid, tagged?, previous, state) do
    state = retire_claim(state, previous)
    token = make_ref()
    monitor = Process.monitor(pid)
    entry = %{key: key, pid: pid, token: token, monitor: monitor, timer: nil, tagged?: tagged?}

    state = %{
      state
      | active: Map.put(state.active, key, token),
        claims: Map.put(state.claims, token, entry),
        monitors: Map.put(state.monitors, monitor, token)
    }

    {:reply, {:ok, token}, state}
  end

  defp active_claim(state, key), do: Map.get(state.claims, Map.get(state.active, key))

  defp retire_claim(state, nil), do: state

  defp retire_claim(state, entry) do
    timer = Process.send_after(self(), {:escalate, entry.token}, state.grace_ms)
    notify_replaced(entry)
    %{state | claims: Map.put(state.claims, entry.token, %{entry | timer: timer})}
  end

  defp notify_replaced(%{tagged?: true} = entry),
    do: send(entry.pid, {:star_view_stream, :replaced, self(), entry.token})

  defp notify_replaced(entry), do: Process.exit(entry.pid, :replaced)

  defp release_owned(state, token, pid) do
    case Map.get(state.claims, token) do
      %{pid: ^pid} -> drop_claim(state, token)
      _ -> state
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {:noreply, drop_claim(state, Map.get(state.monitors, monitor))}
  end

  def handle_info({:escalate, token}, state) do
    escalate(state, token, Map.get(state.claims, token))
  end

  defp escalate(state, token, %{timer: timer, pid: pid}) when not is_nil(timer) do
    Process.exit(pid, :kill)
    {:noreply, drop_claim(state, token)}
  end

  defp escalate(state, _token, _claim), do: {:noreply, state}

  defp drop_claim(state, token) do
    case Map.pop(state.claims, token) do
      {nil, _claims} -> state
      {entry, claims} -> remove_claim(state, token, entry, claims)
    end
  end

  defp remove_claim(state, token, entry, claims) do
    cancel_timer(entry.timer)
    Process.demonitor(entry.monitor, [:flush])
    active = remove_active(state.active, entry.key, token)
    %{state | active: active, claims: claims, monitors: Map.delete(state.monitors, entry.monitor)}
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp remove_active(active, key, token) do
    case Map.get(active, key) do
      ^token -> Map.delete(active, key)
      _ -> active
    end
  end
end
