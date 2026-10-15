defmodule StarView.StreamRefreshTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias Plug.Conn
  alias StarView.Stream
  alias StarView.StreamRegistry

  setup do
    start_supervised!({StreamRegistry, grace_ms: 1_000})
    :ok
  end

  test "the connect snapshot renders after connect without waiting for an invalidation" do
    result = Stream.run(open!(), connect: &mark_connected/1, render: &halt_after_connect/1)
    assert result.assigns.rendered_after_connect
  end

  test "a rejected nested run leaves the outer render lifecycle usable" do
    result = Stream.run(open!(), connect: &attempt_nested_run/1, render: &halt_render/1)
    assert result.assigns.halted_by_render
  end

  defp attempt_nested_run(conn) do
    assert_raise ArgumentError, ~r/nested/, fn -> Stream.run(conn) end
    conn
  end

  test "invalidations queued before the snapshot join it" do
    send_invalidations(3)
    result = Stream.run(open!(), info: &invalidate_or_halt/2, render: &count_render_then_stop/1)
    assert result.assigns.renders == 1
  end

  test "a burst of invalidations renders once" do
    send_invalidations(5)
    opts = [info: &invalidate_or_halt/2, render: &count_render_then_stop/1]
    result = Stream.run(open!(), [render_on_connect: false] ++ opts)
    assert result.assigns.renders == 1
  end

  test "render_interval delays the next render without blocking other messages" do
    opts = [info: &interval_info/2, render: &interval_render/1, render_interval: 50]
    result = Stream.run(open!(), opts)
    [second, first] = result.assigns.render_times
    # The interval runs from the render start, recorded just before `first`.
    assert second - first >= 45
    assert result.assigns.pinged_at < second
  end

  test "stale render tokens are ignored and never reach info" do
    send(self(), {:star_view_stream, :render, make_ref()})
    send(self(), :stop)
    opts = [info: &record_info/2, render: &count_render/1, render_on_connect: false]
    result = Stream.run(open!(), opts)
    assert result.assigns.infos == [:stop]
    refute Map.has_key?(result.assigns, :renders)
  end

  test "a halting render ends the stream and disconnect receives its conn" do
    parent = self()
    disconnect = fn conn -> send(parent, {:disconnected, conn.assigns[:halted_by_render]}) end
    Stream.run(open!(), render: &halt_render/1, disconnect: disconnect)
    assert_receive {:disconnected, true}
  end

  test "normal halts cancel a pending render timer so a reused process can stream again" do
    opts = [info: &invalidate_or_halt/2, render: &schedule_then_stop/1, render_interval: 30]
    Stream.run(open!(), opts)
    refute_receive {:star_view_stream, :render, _token}, 100
    result = Stream.run(open!(), render: &halt_render/1)
    assert result.assigns.halted_by_render
  end

  test "callback errors cancel pending timers and flush queued render messages" do
    opts = [info: &invalidate_or_raise/2, render: &schedule_then_raise/1, render_interval: 30]
    assert_raise RuntimeError, "info failed", fn -> Stream.run(open!(), opts) end
    refute_receive {:star_view_stream, :render, _token}, 100
    send(self(), :invalidate)
    send(self(), :boom)
    opts = [info: &invalidate_or_raise/2, render: &count_render/1, render_on_connect: false]
    assert_raise RuntimeError, "info failed", fn -> Stream.run(open!(), opts) end
    refute_received {:star_view_stream, :render, _token}
  end

  test "invalid render returns and render errors release the claim" do
    {:ok, conn} = Stream.open(keyed_conn("bad-render"), key: :user)
    assert_raise ArgumentError, fn -> Stream.run(conn, render: fn _conn -> :oops end) end
    assert StreamRegistry.owner({:user, "bad-render"}) == :error
    {:ok, conn} = Stream.open(keyed_conn("raise-render"), key: :user)

    assert_raise RuntimeError, "render failed", fn ->
      Stream.run(conn, render: &raise_render/1)
    end

    assert StreamRegistry.owner({:user, "raise-render"}) == :error
  end

  test "invalidate requires a running stream with a render callback" do
    assert_raise ArgumentError, ~r/:render/, fn -> Stream.invalidate(open!()) end
    send(self(), :invalidate)

    assert_raise ArgumentError, ~r/:render/, fn ->
      Stream.run(open!(), info: &invalidate_info/2)
    end
  end

  test "conns from a finished run cannot schedule orphan renders" do
    result = Stream.run(open!(), render: &halt_render/1)
    assert_raise ArgumentError, ~r/running stream/, fn -> Stream.invalidate(result) end
    disconnect_invalidate = [render: &halt_render/1, disconnect: &Stream.invalidate/1]

    assert_raise ArgumentError, ~r/running stream/, fn ->
      Stream.run(open!(), disconnect_invalidate)
    end

    refute_received {:star_view_stream, :render, _token}
  end

  test "a conn from an earlier run cannot schedule into a newer run" do
    earlier = Stream.run(open!(), render: &halt_render/1)
    opts = [connect: fn _conn -> Stream.invalidate(earlier) end, render: &halt_render/1]
    assert_raise ArgumentError, ~r/running stream/, fn -> Stream.run(open!(), opts) end
  end

  test "refresh options are validated" do
    Enum.each(
      [
        [render: :not_a_function],
        [render: &count_render/1, render_interval: -1],
        [render_on_connect: true],
        [render: &count_render/1, render_on_connect: :yes]
      ],
      &assert_invalid_run/1
    )
  end

  defp assert_invalid_run(opts) do
    assert_raise ArgumentError, fn -> Stream.run(open!(), opts) end
  end

  test "Bandit flow-control messages stay in the mailbox when refresh is enabled" do
    send(self(), {:bandit, {:send_window_update, 10}})
    send(self(), :invalidate)
    opts = [info: &invalidate_info/2, render: &halt_render/1, render_on_connect: false]
    Stream.run(open!(), opts)
    assert_receive {:bandit, {:send_window_update, 10}}
  end

  defp open!() do
    {:ok, conn} = Stream.open(conn(:get, "/"))
    conn
  end

  defp keyed_conn(id), do: conn(:post, "/", StarView.JSON.encode!(%{tabId: id}))

  defp send_invalidations(count), do: Enum.each(1..count, fn _ -> send(self(), :invalidate) end)

  defp mark_connected(conn), do: Conn.assign(conn, :connected, true)

  defp halt_after_connect(conn),
    do: {:halt, Conn.assign(conn, :rendered_after_connect, conn.assigns[:connected] == true)}

  defp count_render(conn), do: Conn.assign(conn, :renders, Map.get(conn.assigns, :renders, 0) + 1)

  defp count_render_then_stop(conn) do
    send(self(), :stop)
    count_render(conn)
  end

  defp invalidate_or_halt(:invalidate, conn), do: Stream.invalidate(conn)
  defp invalidate_or_halt(:stop, conn), do: {:halt, conn}

  defp invalidate_info(:invalidate, conn), do: Stream.invalidate(conn)

  defp invalidate_or_raise(:invalidate, conn), do: Stream.invalidate(conn)
  defp invalidate_or_raise(:boom, _conn), do: raise("info failed")

  defp record_info(message, conn) do
    conn = Conn.assign(conn, :infos, Map.get(conn.assigns, :infos, []) ++ [message])
    if message == :stop, do: {:halt, conn}, else: conn
  end

  defp halt_render(conn), do: {:halt, Conn.assign(conn, :halted_by_render, true)}

  defp raise_render(_conn), do: raise("render failed")

  defp schedule_then_stop(conn) do
    send(self(), :invalidate)
    send(self(), :stop)
    conn
  end

  defp schedule_then_raise(conn) do
    send(self(), :invalidate)
    send(self(), :boom)
    conn
  end

  defp interval_render(conn) do
    times = [now() | Map.get(conn.assigns, :render_times, [])]
    conn |> Conn.assign(:render_times, times) |> interval_step(length(times))
  end

  defp interval_step(conn, 1) do
    Enum.each([:invalidate, :ping, :invalidate], &send(self(), &1))
    conn
  end

  defp interval_step(conn, _renders), do: {:halt, conn}

  defp interval_info(:invalidate, conn), do: Stream.invalidate(conn)
  defp interval_info(:ping, conn), do: Conn.assign(conn, :pinged_at, now())

  defp now(), do: System.monotonic_time(:millisecond)
end
