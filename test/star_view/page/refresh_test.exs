defmodule StarView.Page.RefreshTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.Page.Plug, as: PagePlug
  alias StarView.Page.PlugTest.RefreshPage
  alias StarView.Page.PlugTest.StreamPage

  @moduletag :capture_log

  setup do
    {:ok, supervisor: start_supervised!(Task.Supervisor)}
  end

  test "refresh_interval defaults to zero and rejects invalid values" do
    assert StreamPage.__star_view__(:refresh_interval) == 0
    assert RefreshPage.__star_view__(:refresh_interval) == 0
    assert_raise ArgumentError, ~r/refresh_interval/, &compile_invalid_interval_page/0
  end

  test "handle_refresh renders a snapshot after connect, coalesces bursts and skips unchanged HTML",
       %{supervisor: supervisor} do
    task = stream_task(supervisor)
    assert_receive {:refresh_connected, pid}
    assert_receive {:refreshed, ^pid, 0, 1}
    hold(pid)
    Enum.each(1..3, &send(pid, {:changed, &1}))
    send(pid, :release)
    assert_receive {:refreshed, ^pid, 3, 2}
    # Any uncoalesced render was queued before this barrier and would reply first.
    hold(pid)
    send(pid, :release)
    refute_received {:refreshed, ^pid, _version, _renders}
    send(pid, {:changed, 3})
    assert_receive {:refreshed, ^pid, 3, 3}
    send(pid, {:changed, :stop})
    conn = Task.await(task)
    assert content_versions(conn) == ["0", "3"]
    assert_receive {:refresh_disconnected, ^pid, :stop}
  end

  test "a raising refresh propagates after cleanup with the latest completed conn", %{
    supervisor: supervisor
  } do
    task = stream_task(supervisor)
    assert_receive {:refresh_connected, pid}
    send(pid, {:changed, :raise})
    assert {:exit, {%RuntimeError{message: "refresh failed"}, _stacktrace}} = Task.yield(task)
    assert_receive {:refresh_disconnected, ^pid, :raise}
    refute_received {:refresh_disconnected, ^pid, _version}
  end

  test "an invalid refresh return raises ArgumentError", %{supervisor: supervisor} do
    task = stream_task(supervisor)
    assert_receive {:refresh_connected, pid}
    send(pid, {:changed, :bad_return})
    assert {:exit, {%ArgumentError{}, _stacktrace}} = Task.yield(task)
    assert_receive {:refresh_disconnected, ^pid, :bad_return}
  end

  test "pages without handle_refresh keep the existing stream loop", %{supervisor: supervisor} do
    Process.register(self(), :star_view_page_plug_stream_test)
    conn = conn(:post, "/stream")
    task = Task.Supervisor.async_nolink(supervisor, fn -> stream_page(conn) end)
    assert_receive {:connected, pid}
    send(pid, {:star_view_stream, :render, make_ref()})
    send(pid, {:tick, 1})
    send(pid, :halt_now)
    events = task |> Task.await() |> StarView.Test.sse_events()
    assert Enum.map(events, & &1.type) == ["datastar-patch-signals"]
  end

  defp stream_page(conn), do: PagePlug.call(conn, {:stream, StreamPage})

  defp hold(pid) do
    send(pid, {:hold, self()})
    assert_receive {:held, ^pid}
  end

  defp stream_task(supervisor) do
    conn = conn(:post, "/refresh") |> Plug.Conn.assign(:test_pid, self())

    Task.Supervisor.async_nolink(supervisor, fn -> PagePlug.call(conn, {:stream, RefreshPage}) end)
  end

  defp content_versions(conn) do
    conn
    |> StarView.Test.sse_events()
    |> Enum.flat_map(& &1.data)
    |> Enum.flat_map(&content_version/1)
  end

  defp content_version(line) do
    case Regex.run(~r/id="content">([^<]*)</, line) do
      [_match, version] -> [version]
      nil -> []
    end
  end

  defp compile_invalid_interval_page() do
    Code.compile_string("""
    defmodule StarView.Page.RefreshTest.InvalidIntervalPage do
      use StarView.Page, refresh_interval: -1
    end
    """)
  end
end
