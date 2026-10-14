defmodule StarView.Page.PlugTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Test
  import StarView.Test

  alias StarView.Page.Plug, as: PagePlug
  alias StarView.Page.PlugTest.BarePage
  alias StarView.Page.PlugTest.CounterPage
  alias StarView.Page.PlugTest.CrashingConnectPage
  alias StarView.Page.PlugTest.DyingTransportPage
  alias StarView.Page.PlugTest.HaltedPage
  alias StarView.Page.PlugTest.KeyedStreamPage
  alias StarView.Page.PlugTest.LifecyclePage
  alias StarView.Page.PlugTest.MisbehavingStreamPage
  alias StarView.Page.PlugTest.RedirectPage
  alias StarView.Page.PlugTest.RelayAdapter
  alias StarView.Page.PlugTest.RootLayoutPage
  alias StarView.Page.PlugTest.StreamPage
  alias StarView.Page.PlugTest.TestLayouts

  @moduletag :capture_log

  setup do
    supervisor = start_supervised!(Task.Supervisor)
    Process.register(self(), :star_view_page_plug_stream_test)
    {:ok, supervisor: supervisor}
  end

  test "events fetch the raw body conn, start SSE and patch components" do
    conn = event_conn("increment", ~s({"count":2}))
    conn = PagePlug.call(conn, {:event, CounterPage})
    assert conn.state == :chunked
    assert conn.body_params == %{"count" => 2}
    assert_patched_signals(conn, %{count: 3})
    assert_patched_element(conn, "#history")
  end

  test "invalid and oversized signals halt before SSE" do
    for {body, status} <- [
          {"[]", 400},
          {"bad-json", 400},
          {String.duplicate("x", 1_000_001), 413}
        ] do
      conn = PagePlug.call(event_conn("increment", body), {:event, CounterPage})
      assert conn.status == status
      assert conn.state == :sent
      assert conn.halted
    end
  end

  test "an absent event callback returns 404 before SSE" do
    conn = PagePlug.call(event_conn("increment", "{}"), {:event, BarePage})
    assert conn.status == 404
    assert conn.halted
  end

  test "event exceptions are logged by the shared dispatcher and retain their type" do
    log =
      capture_log(fn ->
        assert_raise FunctionClauseError, fn ->
          PagePlug.call(event_conn("explode", "{}"), {:event, CounterPage})
        end
      end)

    assert log =~ "StarView.Dispatch"
    assert log =~ "CounterPage.handle_event"
  end

  test "debug error relay is opt-in and does not hide the event exception" do
    previous = Application.get_env(:star_view, :debug_errors)
    Application.put_env(:star_view, :debug_errors, true)
    on_exit(fn -> restore_debug_errors(previous) end)
    conn = relay_conn(event_conn("explode", "{}"))
    assert_raise FunctionClauseError, fn -> PagePlug.call(conn, {:event, CounterPage}) end
    assert_receive {:sse_chunk, chunk}
    assert chunk =~ "console.error"
    assert chunk =~ "FunctionClauseError"
  end

  test "mount renders, supports an inherited layout override and honors responses" do
    conn = PagePlug.call(conn(:get, "/counter?start=5"), {:page, CounterPage})
    assert conn.status == 200
    assert conn.resp_body =~ ~s(data-signals:count="5")
    assert PagePlug.call(conn(:get, "/bare"), {:page, BarePage}).status == 200
    assert PagePlug.call(conn(:get, "/redirect"), {:page, RedirectPage}).status == 302
    assert PagePlug.call(conn(:get, "/denied"), {:page, HaltedPage}).halted
    assert PagePlug.call(conn(:get, "/"), {:page, RootLayoutPage}).resp_body =~ "root-layout"
    inherited = Phoenix.Controller.put_root_layout(conn(:get, "/"), html: {TestLayouts, :root})
    refute PagePlug.call(inherited, {:page, BarePage}).resp_body =~ "root-layout"
  end

  test "streaming without a connect callback returns 404" do
    assert PagePlug.call(conn(:post, "/bare"), {:stream, BarePage}).status == 404
  end

  test "connect and info use the shared loop and ignore only unmatched callback heads", %{
    supervisor: supervisor
  } do
    task = stream_task(supervisor, StreamPage)
    assert_receive {:connected, pid}
    send(pid, {:tick, 7})
    send(pid, :unmatched_stray)
    send(pid, {:tick, 8})
    send(pid, :halt_now)
    assert_patched_signals(Task.await(task), %{tick: 8})
  end

  test "missing registry returns 503 without connecting" do
    conn = keyed_conn()
    conn = PagePlug.call(conn, {:stream, KeyedStreamPage})
    assert conn.status == 503
    assert conn.halted
    refute_received {:keyed_connected, _pid}
  end

  test "keyed streams use the current registry and release before returning", %{
    supervisor: supervisor
  } do
    start_supervised!(StarView.StreamRegistry)
    task = stream_task(supervisor, KeyedStreamPage, keyed_conn())
    assert_receive {:keyed_connected, pid}
    assert {:ok, ^pid, _generation} = StarView.StreamRegistry.owner({:test_scope, "tab-1"})
    send(pid, :halt_now)
    assert Task.await(task).state == :chunked
    assert StarView.StreamRegistry.owner({:test_scope, "tab-1"}) == :error
  end

  test "unkeyed streams ignore stale legacy takeover messages", %{supervisor: supervisor} do
    task = stream_task(supervisor, StreamPage)
    assert_receive {:connected, pid}
    send(pid, {:EXIT, self(), :replaced})
    send(pid, {:ping, self()})
    assert_receive :pong
    send(pid, :halt_now)
    assert Task.await(task).state == :chunked
  end

  test "invalid callback results and internal FunctionClauseErrors propagate", %{
    supervisor: supervisor
  } do
    for {message, exception} <- [
          {:bad_return, ArgumentError},
          {{:fce_inside, :nope}, FunctionClauseError},
          {:recursive_fce, FunctionClauseError}
        ] do
      task = stream_task(supervisor, MisbehavingStreamPage)
      assert_receive {:connected, pid}
      send(pid, message)
      assert {:exit, {error, _stacktrace}} = Task.yield(task)
      assert error.__struct__ == exception
    end
  end

  test "connect failures propagate and the idle probe ends a closed stream", %{
    supervisor: supervisor
  } do
    task = stream_task(supervisor, CrashingConnectPage)
    assert {:exit, {%RuntimeError{message: "connect exploded"}, _stacktrace}} = Task.yield(task)
    task = stream_task(supervisor, DyingTransportPage)
    assert_receive {:connected, pid}
    send(pid, :kill_transport)
    assert Task.await(task).state == :chunked
  end

  test "normal cleanup gets the latest conn after release and unsubscribes a live owner", %{
    supervisor: supervisor
  } do
    stream_conn = lifecycle_conn()

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        conn = PagePlug.call(stream_conn, {:stream, LifecyclePage})
        send(conn.assigns.test_pid, {:returned, self(), conn})

        receive do
          :finish -> :ok
          message -> send(conn.assigns.test_pid, {:after_stream, message})
        end
      end)

    assert_receive {:connected, pid, %{"tabId" => "lifecycle-tab"}}
    send(pid, :halt)
    assert_receive {:disconnected, ^pid, :halted, :error}
    assert_receive {:returned, ^pid, _conn}
    refute_received {:disconnected, ^pid, _, _}
    Phoenix.PubSub.broadcast(stream_conn.assigns.pubsub, stream_conn.assigns.topic, :later)
    send(pid, :finish)
    assert Task.await(task) == :ok
    refute_received {:after_stream, _message}
  end

  test "raised callbacks clean up once with latest completed conn and preserve the original error",
       %{supervisor: supervisor} do
    stream_conn = lifecycle_conn() |> Plug.Conn.assign(:fail_disconnect, true)
    task = stream_task(supervisor, LifecyclePage, stream_conn)
    assert_receive {:connected, pid, _params}
    send(pid, {:phase, :last_success})
    send(pid, :crash)
    assert {:exit, {%RuntimeError{message: "message failed"}, _stacktrace}} = Task.yield(task)
    assert_receive {:disconnected, ^pid, :last_success, :error}
    refute_received {:disconnected, ^pid, _, _}
  end

  test "connect errors still clean up their subscription and exact claim", %{
    supervisor: supervisor
  } do
    task =
      stream_task(
        supervisor,
        LifecyclePage,
        lifecycle_conn() |> Plug.Conn.assign(:fail_connect, true)
      )

    assert_receive {:connected, pid, _params}
    assert {:exit, {%RuntimeError{message: "connect failed"}, _stacktrace}} = Task.yield(task)
    assert_receive {:disconnected, ^pid, :opening, :error}
    refute_received {:disconnected, ^pid, _, _}
  end

  test "a disconnected write preserves the latest completed callback conn for cleanup", %{
    supervisor: supervisor
  } do
    task = stream_task(supervisor, LifecyclePage, lifecycle_conn())
    assert_receive {:connected, pid, _params}
    send(pid, {:phase, :last_success})
    send(pid, :closed_write)
    assert Task.await(task).assigns.phase == :unfinished_write
    assert_receive {:disconnected, ^pid, :last_success, :error}
    refute_received {:disconnected, ^pid, _, _}
  end

  test "takeover cleans up once and cannot release the new generation", %{supervisor: supervisor} do
    stream_conn = lifecycle_conn()
    old = stream_task(supervisor, LifecyclePage, stream_conn)
    assert_receive {:connected, old_pid, _params}
    send(old_pid, {:phase, :old_success, self()})
    assert_receive {:phase_changed, ^old_pid, :old_success}
    new = stream_task(supervisor, LifecyclePage, stream_conn)
    assert_receive {:connected, new_pid, _params}
    assert_receive {:disconnected, ^old_pid, :old_success, {:ok, ^new_pid, _generation}}
    assert Task.await(old).state == :chunked

    assert {:ok, ^new_pid, _generation} =
             StarView.StreamRegistry.owner({stream_conn.assigns.topic, "lifecycle-tab"})

    send(new_pid, :halt)
    assert Task.await(new).state == :chunked
    assert_receive {:disconnected, ^new_pid, :halted, :error}
    refute_received {:disconnected, ^old_pid, _, _}
  end

  test "a trapped shutdown message releases ownership and cleans up before exiting", %{
    supervisor: supervisor
  } do
    task = stream_task(supervisor, LifecyclePage, lifecycle_conn())
    assert_receive {:connected, pid, _params}
    send(pid, {:EXIT, self(), :shutdown})
    assert Task.yield(task) == {:exit, :shutdown}
    assert_receive {:disconnected, ^pid, :connected, :error}
    refute_received {:disconnected, ^pid, _, _}
  end

  defp lifecycle_conn() do
    start_supervised!(StarView.StreamRegistry)
    pubsub = Module.concat(__MODULE__, PubSub)
    start_supervised!({Phoenix.PubSub, name: pubsub})

    conn(:post, "/stream", ~s({"tabId":"lifecycle-tab"}))
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.assign(:test_pid, self())
    |> Plug.Conn.assign(:topic, "lifecycle-test")
    |> Plug.Conn.assign(:pubsub, pubsub)
    |> Plug.Conn.assign(:phase, :opening)
    |> Plug.Conn.assign(:fail_connect, false)
    |> Plug.Conn.assign(:fail_disconnect, false)
  end

  defp event_conn(event, body) do
    conn(:post, "/counter/_event/#{event}", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Map.put(:path_params, %{"event" => event})
  end

  defp keyed_conn() do
    conn(:post, "/keyed", ~s({"tabId":"tab-1"}))
    |> Plug.Conn.put_req_header("content-type", "application/json")
  end

  defp stream_task(supervisor, page, conn \\ conn(:post, "/stream")) do
    Task.Supervisor.async_nolink(supervisor, fn -> PagePlug.call(conn, {:stream, page}) end)
  end

  defp relay_conn(conn) do
    {_adapter, state} = conn.adapter
    %{conn | adapter: {RelayAdapter, %{inner: state, pid: self()}}}
  end

  defp restore_debug_errors(nil), do: Application.delete_env(:star_view, :debug_errors)

  defp restore_debug_errors(previous),
    do: Application.put_env(:star_view, :debug_errors, previous)
end
