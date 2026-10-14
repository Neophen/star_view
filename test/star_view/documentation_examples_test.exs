defmodule StarView.DocumentationExamplesTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.Documentation.RawCounterEndpoint
  alias StarView.DocumentationWeb.CounterButton
  alias StarView.DocumentationWeb.CounterController
  alias StarView.DocumentationWeb.CounterStreamController
  alias StarView.SSE.TransportError
  alias StarView.TestAssertions
  alias StarView.TransportAdapter

  @pubsub StarView.Documentation.PubSub

  setup_all do
    compile_example("guides/examples/phoenix_counter.md", "MyAppWeb.CounterController")
    compile_example("guides/examples/plug_endpoints.md", "MyApp.RawCounterEndpoint")
    compile_example("guides/examples/pubsub_stream.md", "MyAppWeb.CounterStreamController")
    compile_example("guides/core/actions.md", "MyAppWeb.CounterButton")
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

  defp compile_example(path, module) do
    block =
      path
      |> File.read!()
      |> then(&Regex.scan(~r/```elixir\n(.*?)\n```/s, &1, capture: :all_but_first))
      |> List.flatten()
      |> Enum.find(&String.starts_with?(&1, "defmodule " <> module <> " do"))

    assert is_binary(block), "missing complete example #{module} in #{path}"

    block
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
