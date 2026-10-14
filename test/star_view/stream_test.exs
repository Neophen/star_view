defmodule StarView.StreamTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.Stream
  alias StarView.StreamRegistry
  alias StarView.TransportAdapter

  setup do
    start_supervised!({StreamRegistry, grace_ms: 1_000})
    :ok
  end

  test "callbacks receive the current conn and disconnect runs once after release" do
    {:ok, conn} = Stream.open(keyed_conn("halt"), key: :user)
    parent = self()
    send(self(), :tick)
    send(self(), :stop)

    result =
      Stream.run(conn,
        info: &update/2,
        disconnect: fn conn ->
          send(parent, {:disconnected, conn.assigns.count, StreamRegistry.owner({:user, "halt"})})
        end
      )

    assert result.assigns.count == 1
    assert_receive {:disconnected, 1, :error}
    refute_receive {:disconnected, _, _}
  end

  test "stale tagged and legacy takeover messages do not stop a newer stream" do
    {:ok, conn} = Stream.open(keyed_conn("stale"), key: :user)
    send(self(), {:EXIT, self(), {:replaced, make_ref()}})
    send(self(), {:EXIT, self(), :replaced})
    send(self(), :stop)

    result =
      Stream.run(conn,
        info: fn :stop, conn -> {:halt, Plug.Conn.assign(conn, :stopped, true)} end
      )

    assert result.assigns.stopped
  end

  test "takeover releases the exact generation before replacement callbacks" do
    {:ok, conn} = Stream.open(keyed_conn("takeover"), key: :user)
    parent = self()

    newer =
      start_supervised!({Task, fn -> open_newer(parent, "takeover") end},
        id: make_ref(),
        shutdown: :brutal_kill
      )

    assert_receive {:newer, ^newer}

    result =
      Stream.run(conn,
        replaced: fn message, conn ->
          send(parent, {:replaced, message, StreamRegistry.owner({:user, "takeover"})})
          conn
        end
      )

    assert result == conn
    assert_receive {:replaced, {:EXIT, _, :replaced}, {:ok, ^newer, _token}}
    send(StreamRegistry, {:escalate, conn.private.star_view_stream_claim.token})
    _ = :sys.get_state(StreamRegistry)
    assert {:ok, ^newer, _token} = StreamRegistry.owner({:user, "takeover"})
  end

  test "takeover returns and disconnects default non-trapping owners without killing keep-alive" do
    parent = self()

    owner =
      start_supervised!({Task, fn -> nontrapping_owner(parent, "nontrapping") end},
        id: make_ref(),
        shutdown: :brutal_kill
      )

    assert_receive {:ready, ^owner, {:trap_exit, false}, old_conn}
    assert {:ok, _new_conn} = Stream.open(keyed_conn("nontrapping"), key: :user)
    assert_receive {:disconnected_owner, ^owner}
    assert_receive {:finished_owner, ^owner}
    send(StreamRegistry, {:escalate, old_conn.private.star_view_stream_claim.token})
    _ = :sys.get_state(StreamRegistry)
    send(owner, :ping)
    assert_receive {:pong_owner, ^owner}
  end

  test "Bandit flow-control messages stay in the adapter mailbox" do
    {:ok, conn} = Stream.open(conn(:get, "/"))
    send(self(), {:bandit, {:send_window_update, 10}})
    send(self(), :stop)
    Stream.run(conn, info: fn :stop, conn -> {:halt, conn} end)
    assert_receive {:bandit, {:send_window_update, 10}}
  end

  test "busy streams still probe on a fixed deadline" do
    conn = transport_conn({:notify, self()})
    {:ok, conn} = Stream.open(conn)
    conn = Plug.Conn.assign(conn, :stop_after, System.monotonic_time(:millisecond) + 500)
    send(self(), :busy)
    result = Stream.run(conn, idle_check: 1, info: &busy_info/2)
    assert result.assigns[:probed]
  end

  test "dead idle clients disconnect normally" do
    {:ok, conn} = Stream.open(transport_conn({:error, :closed}))
    parent = self()
    Stream.run(conn, idle_check: 1, disconnect: fn _conn -> send(parent, :disconnected) end)
    assert_receive :disconnected
    refute_receive :disconnected
  end

  test "reset and broken-pipe idle clients disconnect normally" do
    Enum.each([:econnreset, :epipe], &assert_idle_disconnect/1)
  end

  defp assert_idle_disconnect(reason) do
    {:ok, conn} = Stream.open(transport_conn({:error, reason}))
    parent = self()

    Stream.run(conn,
      idle_check: 1,
      disconnect: fn _conn -> send(parent, {:disconnected, reason}) end
    )

    assert_receive {:disconnected, ^reason}
    refute_receive {:disconnected, ^reason}
  end

  test "idle probe errors other than closed propagate" do
    {:ok, conn} = Stream.open(transport_conn({:error, :timeout}))
    assert_raise StarView.SSE.TransportError, fn -> Stream.run(conn, idle_check: 1) end
  end

  test "a closed write preserves the conn passed to the failed write" do
    {:ok, conn} = Stream.open(transport_conn({:error, :closed}))
    send(self(), :write)
    result = Stream.run(conn, info: &failed_write/2)
    assert result.assigns.written
  end

  test "connect crashes and invalid options release the claim" do
    {:ok, conn} = Stream.open(keyed_conn("crash"), key: :user)

    assert_raise RuntimeError, "connect failed", fn ->
      Stream.run(conn, connect: &failed_connect/1)
    end

    assert StreamRegistry.owner({:user, "crash"}) == :error
    {:ok, conn} = Stream.open(keyed_conn("invalid"), key: :user)
    assert_raise ArgumentError, fn -> Stream.run(conn, idle_check: 0) end
    assert StreamRegistry.owner({:user, "invalid"}) == :error
  end

  test "disconnect exceptions propagate after one call and claim release" do
    {:ok, conn} = Stream.open(keyed_conn("disconnect"), key: :user)
    send(self(), :stop)

    assert_raise RuntimeError, "disconnect failed", fn ->
      Stream.run(conn, info: &update/2, disconnect: &failed_disconnect/1)
    end

    assert_receive :disconnect_called
    refute_receive :disconnect_called
    assert StreamRegistry.owner({:user, "disconnect"}) == :error
  end

  test "refused claims return plain 503 and never start SSE" do
    stop_supervised(StreamRegistry)
    assert {:error, conn} = Stream.open(keyed_conn("missing"), key: :user)
    assert conn.status == 503
    assert conn.halted
    assert conn.state == :sent
  end

  defp keyed_conn(id), do: conn(:post, "/", StarView.JSON.encode!(%{tabId: id}))

  defp transport_conn(state) do
    conn = conn(:post, "/", %{})
    %{conn | adapter: {TransportAdapter, state}}
  end

  defp update(:tick, conn),
    do: Plug.Conn.assign(conn, :count, Map.get(conn.assigns, :count, 0) + 1)

  defp update(:stop, conn), do: {:halt, conn}

  defp busy_info(:busy, conn) do
    if System.monotonic_time(:millisecond) >= conn.assigns.stop_after do
      {:halt, conn}
    else
      send(self(), :busy)
      conn
    end
  end

  defp busy_info({:chunk, ": \n\n"}, conn), do: {:halt, Plug.Conn.assign(conn, :probed, true)}

  defp failed_write(:write, conn) do
    conn |> Plug.Conn.assign(:written, true) |> StarView.patch_signals(%{saved: true})
  end

  defp failed_connect(_conn), do: raise("connect failed")

  defp failed_disconnect(_conn) do
    send(self(), :disconnect_called)
    raise "disconnect failed"
  end

  defp open_newer(parent, tab_id) do
    {:ok, conn} = Stream.open(keyed_conn(tab_id), key: :user)
    send(parent, {:newer, self()})

    receive do
      :stop -> StreamRegistry.release(conn)
    end
  end

  defp nontrapping_owner(parent, tab_id) do
    {:ok, conn} = Stream.open(keyed_conn(tab_id), key: :user)
    send(parent, {:ready, self(), Process.info(self(), :trap_exit), conn})
    Stream.run(conn, disconnect: fn _conn -> send(parent, {:disconnected_owner, self()}) end)
    send(parent, {:finished_owner, self()})
    keep_alive(parent)
  end

  defp keep_alive(parent) do
    receive do
      :ping -> send(parent, {:pong_owner, self()})
    end
  end
end
