defmodule Mix.Tasks.StarView.Setup.StreamPageTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "generates the stream demo page, ticker, and wiring" do
    igniter =
      phoenix_project()
      |> Igniter.compose_task("star_view.setup.stream_page")

    page = file_content(igniter, "lib/octafest_web/stream_demo_page.ex")

    assert page =~ "defmodule OctafestWeb.StreamDemoPage do"
    assert page =~ "use StarView.Page"
    assert page =~ "alias OctafestWeb.Components.StarView.Layout"
    assert page =~ "<Layout.app conn={@conn}>"
    assert page =~ "data-init={connect()}"
    assert page =~ "Phoenix.PubSub.subscribe(Octafest.PubSub, Octafest.DemoTicker.topic())"
    assert page =~ "def handle_info({:tick, time}, conn) do"
    assert page =~ "def handle_disconnect(conn) do"
    assert page =~ "Phoenix.PubSub.unsubscribe(Octafest.PubSub, Octafest.DemoTicker.topic())"
    assert page =~ "patch_signals(conn, %{time: time, tick: conn.assigns.tick})"

    ticker = file_content(igniter, "lib/octafest/demo_ticker.ex")

    assert ticker =~ "defmodule Octafest.DemoTicker do"
    assert ticker =~ "use GenServer"

    assert ticker =~
             ~s|Phoenix.PubSub.broadcast(Octafest.PubSub, @topic, {:tick, formatted_time()})|

    assert ticker =~ "@impl GenServer"

    application = file_content(igniter, "lib/octafest/application.ex")

    assert application =~ "Octafest.DemoTicker"
    assert_before(application, "Phoenix.PubSub", "Octafest.DemoTicker")

    router = file_content(igniter, "lib/octafest_web/router.ex")

    assert router =~ "import StarView.Router"
    assert router =~ ~r|star_view\(?"/stream-demo", StreamDemoPage\)?|
    assert_before(router, "use OctafestWeb, :router", "import StarView.Router")
    assert_before(router, "plug StarView.Plug.RenameCsrfParam", "plug(:protect_from_forgery)")

    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")
    assert layout =~ "def app(assigns) do"
  end

  test "is idempotent when run twice" do
    igniter =
      phoenix_project()
      |> Igniter.compose_task("star_view.setup.stream_page")
      |> Mix.Tasks.StarView.Setup.StreamPage.igniter()

    router = file_content(igniter, "lib/octafest_web/router.ex")

    assert count_occurrences(router, ~s|"/stream-demo", StreamDemoPage|) == 1
    assert count_occurrences(router, "import StarView.Router") == 1

    application = file_content(igniter, "lib/octafest/application.ex")
    assert count_occurrences(application, "Octafest.DemoTicker") == 1
  end

  defp phoenix_project() do
    igniter = phx_test_project(app_name: :octafest)

    Enum.reduce(
      Map.keys(igniter.assigns.test_files),
      igniter,
      &Igniter.include_existing_file(&2, &1)
    )
  end

  defp file_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end

  defp assert_before(source, first, second) do
    {first_index, _} = :binary.match(source, first)
    {second_index, _} = :binary.match(source, second)

    assert first_index < second_index
  end
end
