defmodule StarView.StreamRegistryTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.StreamRegistry
  alias StarView.TransportAdapter

  setup do
    start_supervised!({StreamRegistry, grace_ms: 1_000})
    :ok
  end

  test "manual replacement atomically becomes owner and preserves the legacy exit reason" do
    key = {:user, "manual"}
    first = start_owner(key, false)
    assert_receive {:claimed, ^first, :ok}
    ref = Process.monitor(first)
    assert :ok = StreamRegistry.replace_and_register(key)
    assert_receive {:DOWN, ^ref, :process, ^first, :replaced}
    assert {:ok, pid, token} = StreamRegistry.owner(key)
    assert pid == self()
    assert is_reference(token)
  end

  test "claiming the same key from the same process is idempotent" do
    key = {:user, "same"}
    assert :ok = StreamRegistry.replace_and_register(key)
    assert {:ok, pid, token} = StreamRegistry.owner(key)
    assert :ok = StreamRegistry.replace_and_register(key)
    assert StreamRegistry.owner(key) == {:ok, pid, token}
  end

  test "concurrent claims are ordered and leave exactly one active owner" do
    key = {:user, "race"}
    owners = Enum.map(1..12, fn _ -> start_owner(key, true, :barrier) end)
    Enum.each(owners, &send(&1, :claim))

    claimed =
      Enum.map(owners, fn _ ->
        assert_receive({:claimed, pid, :ok}, 1_000)
        pid
      end)

    assert MapSet.new(claimed) == MapSet.new(owners)
    assert {:ok, last, token} = StreamRegistry.owner(key)

    replaced =
      Enum.map(1..11, fn _ ->
        assert_receive({:released, pid}, 1_000)
        pid
      end)

    assert MapSet.new(replaced) == MapSet.new(owners -- [last])
    assert StreamRegistry.owner(key) == {:ok, last, token}
  end

  test "released keep-alive owner is never killed by its old escalation" do
    key = {:user, "keepalive"}
    first = start_owner(key, true)
    assert_receive {:claimed, ^first, :ok}
    assert {:ok, ^first, token} = StreamRegistry.owner(key)
    assert :ok = StreamRegistry.replace_and_register(key)
    assert_receive {:released, ^first}
    send(StreamRegistry, {:escalate, token})
    _ = :sys.get_state(StreamRegistry)
    send(first, :ping)
    assert_receive {:pong, ^first}
  end

  test "late release of an old conn cannot remove a newer generation on the same process" do
    Process.flag(:trap_exit, true)
    original = StreamRegistry.start_stream(stream_conn("late"), :user)
    assert {:ok, pid, token} = StreamRegistry.owner({:user, "late"})
    assert pid == self()
    other = start_owner({:user, "late"}, true)
    assert_receive {:claimed, ^other, :ok}
    newer = StreamRegistry.start_stream(stream_conn("late"), :user)
    assert {:ok, ^pid, newer_token} = StreamRegistry.owner({:user, "late"})
    refute newer_token == token
    assert :ok = StreamRegistry.release(original)
    assert StreamRegistry.owner({:user, "late"}) == {:ok, self(), newer_token}
    send(StreamRegistry, {:escalate, token})
    _ = :sys.get_state(StreamRegistry)
    assert :ok = StreamRegistry.release(newer)
    assert StreamRegistry.owner({:user, "late"}) == :error
  end

  test "uncooperative retired owners are escalated without removing the new owner" do
    key = {:user, "stuck"}
    parent = self()

    stuck =
      start_supervised!({Task, fn -> uncooperative(parent, key) end},
        id: make_ref(),
        shutdown: :brutal_kill
      )

    assert_receive {:claimed, ^stuck, :ok}
    assert {:ok, ^stuck, token} = StreamRegistry.owner(key)
    ref = Process.monitor(stuck)
    assert :ok = StreamRegistry.replace_and_register(key)
    send(StreamRegistry, {:escalate, token})
    assert_receive {:DOWN, ^ref, :process, ^stuck, :killed}
    assert {:ok, owner, _token} = StreamRegistry.owner(key)
    assert owner == self()
  end

  test "missing or unusable tab ids retain the unkeyed fallback" do
    assert StreamRegistry.start_stream(conn(:get, "/"), :user).state == :chunked
    Enum.each([nil, "", " ", 123, %{}, String.duplicate("a", 257)], &assert_unkeyed/1)
  end

  test "keyed stream stores its claim and releases it explicitly" do
    conn = StreamRegistry.start_stream(stream_conn("abc"), :user)
    assert conn.state == :chunked
    assert {:ok, pid, token} = StreamRegistry.owner({:user, "abc"})
    assert pid == self()
    assert conn.private.star_view_stream_claim.token == token
    assert StreamRegistry.unregister_stream(conn) == conn
    assert StreamRegistry.owner({:user, "abc"}) == :error
  end

  test "coordinator errors fail closed before SSE" do
    stop_supervised(StreamRegistry)
    assert {:error, _reason} = StreamRegistry.replace_and_register({:user, "offline"})
    conn = StreamRegistry.start_stream(stream_conn("offline"), :user)
    assert conn.status == 503
    assert conn.state == :sent
    assert conn.halted
    assert StreamRegistry.start_stream(conn(:get, "/"), :user).state == :chunked
  end

  test "malformed signals and oversized payloads never claim or start SSE" do
    invalid = StreamRegistry.start_stream(conn(:post, "/", "{"), :user)
    assert invalid.status == 400
    assert invalid.halted
    oversized = StreamRegistry.start_stream(stream_conn("large"), :user, max_bytes: 2)
    assert oversized.status == 413
    assert oversized.halted
    assert StreamRegistry.owner({:user, "large"}) == :error
  end

  test "a failed SSE start releases the claim" do
    conn = stream_conn("start-failure")

    conn = %{
      conn
      | adapter: {TransportAdapter, {:start_error, "adapter unavailable"}},
        body_params: %{"tabId" => "start-failure"}
    }

    assert_raise RuntimeError, "adapter unavailable", fn ->
      StreamRegistry.start_stream(conn, :user)
    end

    assert StreamRegistry.owner({:user, "start-failure"}) == :error
  end

  defp stream_conn(tab_id), do: conn(:post, "/", StarView.JSON.encode!(%{tabId: tab_id}))

  defp assert_unkeyed(tab_id) do
    assert StreamRegistry.start_stream(stream_conn(tab_id), :user).state == :chunked
    assert StreamRegistry.owner({:user, tab_id}) == :error
  end

  defp start_owner(key, trap?, mode \\ :immediate) do
    parent = self()

    start_supervised!({Task, fn -> owner(parent, key, trap?, mode) end},
      id: make_ref(),
      shutdown: :brutal_kill
    )
  end

  defp owner(parent, key, trap?, mode) do
    Process.flag(:trap_exit, trap?)
    await_barrier(mode)
    result = StreamRegistry.replace_and_register(key)
    send(parent, {:claimed, self(), result})
    owner_loop(parent)
  end

  defp await_barrier(:immediate), do: :ok

  defp await_barrier(:barrier) do
    receive do
      :claim -> :ok
    end
  end

  defp owner_loop(parent) do
    receive do
      {:EXIT, _pid, :replaced} ->
        StreamRegistry.unregister_self()
        send(parent, {:released, self()})
        owner_loop(parent)

      :ping ->
        send(parent, {:pong, self()})
        owner_loop(parent)

      :stop ->
        StreamRegistry.unregister_self()
    end
  end

  defp uncooperative(parent, key) do
    Process.flag(:trap_exit, true)
    result = StreamRegistry.replace_and_register(key)
    send(parent, {:claimed, self(), result})

    receive do
      :stop -> :ok
    end
  end
end
