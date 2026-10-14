defmodule StarView.PageTest do
  use ExUnit.Case, async: true

  alias StarView.PageTest.CounterPage
  alias StarView.PageTest.TunedPage

  defp render_to_string(rendered) do
    rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
  end

  test "render/1 produces HEEx with the page-local event helper" do
    html = render_to_string(CounterPage.render(%{count: 0}))
    assert html =~ "data-signals:count"

    assert html =~ "location.pathname"
    assert html =~ "invalid StarView path"
    assert html =~ "/_event/increment"
  end

  test "the assign shim works on conns inside mount" do
    conn = Plug.Test.conn(:get, "/") |> CounterPage.mount(%{})
    assert conn.assigns.count == 0
    assert conn.assigns.title == "Counter"
  end

  test "idle_check defaults to 30 seconds and is tunable per page" do
    assert CounterPage.__star_view__(:idle_check) == 30_000
    assert TunedPage.__star_view__(:idle_check) == 50
  end
end
