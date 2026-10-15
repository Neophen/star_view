defmodule StarView.DocumentationExamplesTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.Documentation.RawCounterEndpoint
  alias StarView.DocumentationWeb.CounterButton
  alias StarView.DocumentationWeb.CounterController
  alias StarView.DocumentationWeb.CounterPage
  alias StarView.DocumentationWeb.CounterStreamController
  alias StarView.DocumentationWeb.DashboardPage
  alias StarView.DocumentationWeb.DetailDrawer
  alias StarView.DocumentationWeb.OrdersPage
  alias StarView.SSE.TransportError
  alias StarView.TestAssertions
  alias StarView.TransportAdapter

  @pubsub StarView.Documentation.PubSub

  setup_all do
    compile_example("guides/examples/phoenix_counter.md", "MyAppWeb.CounterController")
    compile_example("guides/examples/plug_endpoints.md", "MyApp.RawCounterEndpoint")
    compile_example("guides/examples/pubsub_stream.md", "MyAppWeb.CounterStreamController")
    compile_example("guides/examples/reactive_rendering.md", "MyAppWeb.OrdersPage")
    compile_example("guides/core/actions.md", "MyAppWeb.CounterButton")
    compile_example("guides/phoenix/pages.md", "MyAppWeb.CounterPage")
    compile_example("guides/phoenix/pages.md", "MyAppWeb.DashboardPage")
    compile_example("guides/phoenix/pages.md", "MyAppWeb.DetailDrawer")
    :ok
  end

  test "complete counter example renders initial state and patches a component using assign" do
    initial = apply(CounterController, :mount, [conn(:get, "/counter"), %{}])
    assigns = initial.assigns |> Map.put(:conn, initial) |> Map.put(:__changed__, nil)
    html = CounterController |> apply(:render, [assigns]) |> html_string()
    assert html =~ "Count: 0"
    assert html =~ "counter-increment"
    assert html =~ "data-signals="

    result = dispatch_counter(%{count: 2})
    assert {200, _headers, body} = TestAssertions.chunked_resp(result)
    assert body =~ ~s(data: signals {"count":3})
    assert body =~ "Count: 3</output>"
  end

  test "reactive page example renders backend data and stops a forbidden refresh" do
    scope = %{organization: %{id: "festival"}, orders: [%{id: "one", number: "Order 1"}]}
    conn = conn(:post, "/orders") |> Plug.Conn.assign(:current_scope, scope)
    initial = apply(OrdersPage, :mount, [conn, %{}])
    assigns = initial.assigns |> Map.put(:conn, initial) |> Map.put(:__changed__, nil)
    html = OrdersPage |> apply(:render, [assigns]) |> html_string()
    assert html =~ "Order 1"
    assert html =~ "data-init="

    streaming = StarView.start(conn)
    updated = apply(OrdersPage, :handle_refresh, [streaming])
    StarView.Test.assert_patched_element(updated, "#orders")

    forbidden = Plug.Conn.assign(streaming, :current_scope, %{allowed?: false})
    assert {:halt, ^forbidden} = apply(OrdersPage, :handle_refresh, [forbidden])

    denied_request = Plug.Conn.assign(conn, :current_scope, %{allowed?: false})
    denied = apply(OrdersPage, :mount, [denied_request, %{}])
    assert denied.status == 403
    assert denied.halted
  end

  test "counter guards reject client counts without changing count or patching the summary" do
    Enum.each([-1, 1_000_000, "3", nil], &assert_counter_rejection/1)
  end

  test "complete raw Plug example threads the conn and distinguishes HTTP errors from SSE" do
    result = raw_counter(conn(:post, "/", ~s({"count":4})))
    assert {200, _headers, body} = TestAssertions.chunked_resp(result)
    assert body =~ ~s(data: signals {"count":5})
    assert result.body_params == %{"count" => 4}

    Enum.each(["{", "[]", "null", ~s({"count":"bad"})], &assert_raw_rejection/1)
    oversized = raw_counter(conn(:post, "/", String.duplicate(" ", 8_193)))
    assert oversized.status == 413
    assert oversized.state == :sent
    get = raw_counter(conn(:get, "/"))
    assert get.status == 405
    assert Plug.Conn.get_resp_header(get, "allow") == ["POST"]
  end

  test "shared component example targets the controller without becoming dispatchable" do
    html = apply(CounterButton, :button, [%{__changed__: nil}]) |> html_string()
    assert html =~ "star_view-documentation_web-counter_controller/increment"
    assert html =~ "@post(&quot;"
    refute function_exported?(CounterButton, :__star_view_handler__, 0)
  end

  test "complete PubSub example patches updates and releases both subscription and stream claim" do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    start_supervised!(StarView.StreamRegistry)
    parent = self()
    child = start_supervised!({Task, fn -> run_stream_example(parent) end}, id: make_ref())

    trace_stream_subscription(child)
    send(child, :run)

    assert_receive {:trace, ^child, :return_from, {CounterStreamController, :subscribe, 1},
                    %Plug.Conn{}},
                   1_000

    :ok = Phoenix.PubSub.broadcast(@pubsub, "counter:reader", {:counter_changed, 42})
    :ok = Phoenix.PubSub.broadcast(@pubsub, "counter:reader", :stop_counter_stream)
    assert_receive {:stream_finished, ^child, result, []}, 1_000
    assert {200, _headers, body} = TestAssertions.chunked_resp(result)
    assert body =~ ~s(data: signals {"count":42})
    assert StarView.StreamRegistry.owner({{:counter, "reader"}, "doc-tab"}) == :error
  end

  test "PubSub example unsubscribes even when a non-disconnect write error propagates" do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    start_supervised!(StarView.StreamRegistry)
    parent = self()
    child = start_supervised!({Task, fn -> failed_stream_example(parent) end}, id: make_ref())
    trace_stream_subscription(child)
    send(child, :run)

    assert_receive {:trace, ^child, :return_from, {CounterStreamController, :subscribe, 1},
                    %Plug.Conn{}},
                   1_000

    :ok = Phoenix.PubSub.broadcast(@pubsub, "counter:reader", {:counter_changed, 42})
    assert_receive {:stream_failed, ^child, %TransportError{reason: :timeout}, []}, 1_000
    assert StarView.StreamRegistry.owner({{:counter, "reader"}, "doc-tab"}) == :error
  end

  test "complete page example renders and its method/count guards protect mutation clauses" do
    initial = StarView.Page.Plug.call(conn(:get, "/counter"), {:page, CounterPage})
    assert initial.status == 200
    assert initial.resp_body =~ ~s(id="increment")
    conn = page_event(:post, %{"count" => 2})
    StarView.Test.assert_patched_signals(conn, %{count: 3})
    StarView.Test.assert_patched_element(conn, "#history")

    for count <- ["2", -1, 1_000_000, nil] do
      assert StarView.Test.patched_signals(page_event(:post, %{"count" => count})) == %{}
    end

    assert StarView.Test.patched_signals(page_event(:get, %{"count" => 2})) == %{}
  end

  test "complete shared event component compiles and guards its submitted values" do
    html =
      apply(DetailDrawer, :drawer, [%{__changed__: nil, item: %{id: "id/123"}}]) |> html_string()

    assert html =~ "change_title%3Aid%2F123"
    encoded = StarView.Actions.encode_module(DetailDrawer)
    conn = conn(:post, "/", ~s({"title":"New title"}))
    conn = %{conn | path_params: %{"module" => encoded, "event" => "change_title:id/123"}}
    result = StarView.Dispatch.call(conn, [])
    StarView.Test.assert_patched_signals(result, %{saved: true})
  end

  test "complete page stream example unsubscribes under a reusable owner" do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    parent = self()
    child = start_supervised!({Task, fn -> run_page_stream_example(parent) end}, id: make_ref())
    :erlang.trace_pattern({DashboardPage, :handle_connect, 2}, [{:_, [], [{:return_trace}]}], [])
    :erlang.trace(child, true, [:call])
    on_exit(fn -> :erlang.trace_pattern({DashboardPage, :handle_connect, 2}, false, []) end)
    send(child, :run)

    assert_receive {:trace, ^child, :return_from, {DashboardPage, :handle_connect, 2},
                    %Plug.Conn{}},
                   1_000

    Phoenix.PubSub.broadcast(@pubsub, "orders", {:order_count, 42})
    Phoenix.PubSub.broadcast(@pubsub, "orders", :done)
    assert_receive {:page_stream_finished, ^child, result, []}, 1_000
    StarView.Test.assert_patched_signals(result, %{orders: 42})
  end

  defp page_event(:get, signals) do
    query = URI.encode_query(%{"datastar" => StarView.JSON.encode!(signals)})
    conn = conn(:get, "/counter/_event/increment?#{query}")
    conn = %{conn | path_params: %{"event" => "increment"}}
    StarView.Page.Plug.call(conn, {:event, CounterPage})
  end

  defp page_event(method, signals) do
    conn = conn(method, "/counter/_event/increment", StarView.JSON.encode!(signals))
    conn = %{conn | path_params: %{"event" => "increment"}}
    StarView.Page.Plug.call(conn, {:event, CounterPage})
  end

  defp run_page_stream_example(parent) do
    receive do
      :run -> :ok
    end

    result = StarView.Page.Plug.call(conn(:post, "/dashboard"), {:stream, DashboardPage})
    send(parent, {:page_stream_finished, self(), result, Registry.keys(@pubsub, self())})
  end

  defp compile_example(path, module) do
    block =
      path
      |> File.read!()
      |> then(&Regex.scan(~r/```elixir\n(.*?)\n```/s, &1, capture: :all_but_first))
      |> List.flatten()
      |> Enum.find(&String.starts_with?(&1, "defmodule " <> module <> " do"))

    assert is_binary(block), "missing complete example #{module} in #{path}"

    block
    |> String.replace(
      "alias MyAppWeb.Components.StarView.Layout",
      "alias StarView.DocumentationLayout, as: Layout"
    )
    |> String.replace("MyAppWeb", "StarView.DocumentationWeb")
    |> String.replace("MyApp.", "StarView.Documentation.")
    |> Code.compile_string(path)
  end

  defp html_string(rendered),
    do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp dispatch_counter(signals) do
    conn = conn(:post, "/", StarView.JSON.encode!(signals))

    conn = %{
      conn
      | path_params: %{
          "module" => StarView.Actions.encode_module(CounterController),
          "event" => "increment"
        }
    }

    StarView.Dispatch.call(conn, [])
  end

  defp assert_counter_rejection(count) do
    result = dispatch_counter(%{count: count})
    assert {200, _headers, body} = TestAssertions.chunked_resp(result)
    assert body =~ "counter_error"
    refute body =~ "data: elements"
    refute body =~ ~s(data: signals {"count":)
  end

  # These modules are compiled from the published Markdown during setup_all.
  defp raw_counter(conn), do: apply(RawCounterEndpoint, :call, [conn, []])

  defp assert_raw_rejection(body) do
    result = raw_counter(conn(:post, "/", body))
    assert result.status == 400
    assert result.state == :sent
    assert result.halted
  end

  defp trace_stream_subscription(child) do
    :erlang.trace_pattern(
      {CounterStreamController, :subscribe, 1},
      [{:_, [], [{:return_trace}]}],
      [:local]
    )

    :erlang.trace(child, true, [:call])

    on_exit(fn ->
      :erlang.trace_pattern({CounterStreamController, :subscribe, 1}, false, [:local])
    end)
  end

  defp failed_stream_example(parent) do
    run_stream_example(parent, {TransportAdapter, {:error, :timeout}})
  rescue
    exception in TransportError ->
      send(parent, {:stream_failed, self(), exception, Registry.keys(@pubsub, self())})
  end

  defp run_stream_example(parent, adapter \\ nil) do
    receive do
      :run -> :ok
    end

    query = URI.encode_query(%{"datastar" => ~s({"tabId":"doc-tab"})})

    conn =
      conn(:get, "/counter/events?#{query}") |> Plug.Conn.assign(:current_user, %{id: "reader"})

    conn = with_adapter(conn, adapter)
    result = apply(CounterStreamController, :show, [conn, %{}])
    send(parent, {:stream_finished, self(), result, Registry.keys(@pubsub, self())})
  end

  defp with_adapter(conn, nil), do: conn
  defp with_adapter(conn, adapter), do: %{conn | adapter: adapter}
end
