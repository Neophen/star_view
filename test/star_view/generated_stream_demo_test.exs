defmodule StarView.GeneratedStreamDemoTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import StarView.Test

  @pubsub StarView.GeneratedDemoPubSub
  @ticker StarView.GeneratedDemoTicker
  @page StarView.GeneratedDemoPage

  setup_all do
    ticker = EEx.eval_file("priv/templates/demo_ticker.ex.eex", pubsub_module: @pubsub)

    page =
      EEx.eval_file("priv/templates/stream_demo_page.ex.eex",
        pubsub_module: @pubsub,
        ticker_module: @ticker,
        layout_module: StarView.GeneratedDemo.Layout
      )

    compile_generated(@ticker, ticker)
    compile_generated(@page, page)
    :ok
  end

  test "generated ticker is supervised and page callbacks patch and unsubscribe" do
    start_supervised!({Phoenix.PubSub, name: @pubsub})
    start_supervised!(@ticker)
    topic = apply(@ticker, :topic, [])
    Phoenix.PubSub.subscribe(@pubsub, topic)
    assert_receive {:tick, time}, 1_500
    assert is_binary(time)
    Phoenix.PubSub.unsubscribe(@pubsub, topic)
    initial = StarView.Page.Plug.call(conn(:get, "/stream-demo"), {:page, @page})
    assert initial.status == 200
    assert initial.resp_body =~ "SSE Stream Demo"
    conn = conn(:post, "/stream-demo") |> StarView.SSE.start()
    conn = apply(@page, :handle_connect, [conn, %{}])
    assert topic in Registry.keys(@pubsub, self())
    conn = apply(@page, :handle_info, [{:tick, time}, conn])
    assert_patched_signals(conn, %{time: time, tick: 1})
    apply(@page, :handle_disconnect, [conn])
    assert Registry.keys(@pubsub, self()) == []
  end

  defp compile_generated(module, body) do
    Code.compile_string("defmodule #{inspect(module)} do\n#{body}\nend")
  end
end
