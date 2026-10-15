defmodule StarView.ElementsOnlyChangedTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarView.Stream
  alias StarView.Stream.RenderState

  @html ~s(<div id="orders">1</div>)
  @changed ~s(<div id="orders">2</div>)

  test "unchanged HTML under one key is skipped and changed HTML is sent" do
    patches = [{@html, key: :orders}, {@html, key: :orders}, {@changed, key: :orders}]
    assert patched_html(patches) == [@html, @changed]
  end

  test "returning to earlier HTML after a change is sent again" do
    patches = [{@html, key: :orders}, {@changed, key: :orders}, {@html, key: :orders}]
    assert patched_html(patches) == [@html, @changed, @html]
  end

  test "distinct keys are tracked independently" do
    assert length(patched_html([{@html, key: :left}, {@html, key: :right}])) == 2
  end

  test "different selector, mode, namespace or view transition counts as a change" do
    Enum.each(
      [
        [selector: "#orders"],
        [mode: :inner],
        [mode: :replace],
        [namespace: :svg],
        [use_view_transition: true]
      ],
      &assert_option_change_sent/1
    )
  end

  test "changed SSE event identity or retry metadata is sent even with identical HTML" do
    Enum.each([[event_id: "next-event"], [retry: 2_000]], &assert_option_change_sent/1)
  end

  test "non-idempotent modes are rejected" do
    Enum.each([:append, :prepend, :before, :after], &assert_rejected_mode/1)
    assert_raise ArgumentError, ~r/modes/, fn -> run_patches(&remove_only_changed/1) end
  end

  test "repeated append patches without only_changed are all sent" do
    patches = [
      {@html, mode: :append, selector: "#list"},
      {@html, mode: :append, selector: "#list"}
    ]

    assert length(run_events(patches, [])) == 2
  end

  test "only_changed requires a boolean flag and an explicit key" do
    assert_raise ArgumentError, ~r/:key/, fn -> run_events([{@html, []}]) end
    assert_raise ArgumentError, ~r/:key/, fn -> run_events([{@html, key: nil}]) end

    assert_raise ArgumentError, ~r/boolean/, fn ->
      run_events([{@html, []}], only_changed: :yes)
    end
  end

  test "conns outside Stream.run always send" do
    conn = StarView.start(conn(:post, "/"))
    conn = conn |> patch_only_changed(@html) |> patch_only_changed(@html)
    assert length(element_events(conn)) == 2
  end

  test "a new run starts with empty fingerprints" do
    patches = [{@html, key: :orders, only_changed: true}]
    conn = open!() |> run_stream(patches) |> run_stream(patches)
    assert length(element_events(conn)) == 2
  end

  test "retained fingerprints are bounded per stream" do
    limit = RenderState.max_fingerprints()
    tracked = Enum.map(1..limit, &{@html, key: &1})
    overflow = [{@html, key: :overflow}, {@html, key: :overflow}, {@html, key: 1}]
    assert length(patched_html(tracked ++ overflow)) == limit + 2
  end

  test "an ordinary patch of the same target makes the next keyed patch send again" do
    steps = [keyed(@html), {@changed, []}, keyed(@html)]
    assert step_html(steps) == [@html, @changed, @html]
  end

  test "a removal or script makes the next keyed patch send again" do
    remove = &StarView.remove_elements(&1, "#orders")
    script = &StarView.execute_script(&1, "console.log('x')")
    assert length(step_events([keyed(@html), remove, keyed(@html)])) == 3
    assert length(step_events([keyed(@html), script, keyed(@html)])) == 3
  end

  test "an ordinary patch conservatively clears unrelated keys" do
    steps = [keyed(@html, :left), {@changed, selector: "#other"}, keyed(@html, :left)]
    assert step_html(steps) == [@html, @changed, @html]
  end

  test "a keyed send does not clear other keys" do
    steps = [keyed(@html, :left), keyed(@changed, :right), keyed(@html, :left)]
    assert step_html(steps) == [@html, @changed]
  end

  test "a conn returned from a finished run no longer suppresses patches" do
    conn = run_stream(open!(), [keyed(@html)])
    conn = patch_only_changed(conn, @html)
    assert length(element_events(conn)) == 2
  end

  defp keyed(html, key \\ :orders), do: {html, key: key, only_changed: true}

  defp step_html(steps) do
    steps |> step_events() |> Enum.flat_map(& &1.data) |> Enum.flat_map(&element_html/1)
  end

  defp step_events(steps), do: open!() |> run_stream(steps) |> element_events()

  defp assert_option_change_sent(opts) do
    patches = [{@html, key: :orders}, {@html, [key: :orders] ++ opts}]
    assert length(patched_html(patches)) == 2
  end

  defp assert_rejected_mode(mode) do
    assert_raise ArgumentError, ~r/modes/, fn -> run_events([{@html, key: :list, mode: mode}]) end
  end

  defp remove_only_changed(conn),
    do: StarView.remove_elements(conn, "#orders", key: :orders, only_changed: true)

  defp patch_only_changed(conn, html),
    do: StarView.patch_elements(conn, html, key: :orders, only_changed: true)

  defp patched_html(patches) do
    patches |> run_events() |> Enum.flat_map(& &1.data) |> Enum.flat_map(&element_html/1)
  end

  defp element_html("elements " <> html), do: [html]
  defp element_html(_line), do: []

  defp run_events(patches, extra \\ [only_changed: true]) do
    patches
    |> Enum.map(&with_options(&1, extra))
    |> then(&run_stream(open!(), &1))
    |> element_events()
  end

  defp with_options({html, opts}, extra), do: {html, extra ++ opts}

  defp run_patches(connect) do
    send(self(), :stop)
    Stream.run(open!(), connect: connect, info: &halt/2)
  end

  defp run_stream(conn, patches) do
    send(self(), :stop)
    Stream.run(conn, connect: &apply_patches(&1, patches), info: &halt/2)
  end

  defp apply_patches(conn, patches), do: Enum.reduce(patches, conn, &apply_patch/2)

  defp apply_patch({html, opts}, conn), do: StarView.patch_elements(conn, html, opts)
  defp apply_patch(step, conn) when is_function(step, 1), do: step.(conn)

  defp halt(:stop, conn), do: {:halt, conn}

  defp open!() do
    {:ok, conn} = Stream.open(conn(:get, "/"))
    conn
  end

  defp element_events(conn) do
    conn |> StarView.Test.sse_events() |> Enum.filter(&(&1.type == "datastar-patch-elements"))
  end
end
