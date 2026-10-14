defmodule StarView.Page.HelpersTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import StarView.Page.Helpers

  alias StarView.Page.HelpersTest.AssigningComponent
  alias StarView.TestAssertions

  test "page events preserve literal segments and use a local pathname" do
    assert event("increment") =~ "location.pathname"
    assert event("increment") =~ "invalid StarView path"
    assert event("increment") =~ ~s(+ "/_event/increment")

    assert event("toggle:ABC.123") =~ "/_event/toggle%3AABC%2E123"
    assert event("a/b'\"č") =~ "/_event/a%2Fb%27%22%C4%8D"
    assert event("remove", verb: :delete) =~ "@delete("
    assert event("save", opts: "{retryMaxCount: 5}") =~ ", {retryMaxCount: 5})"
  end

  test "empty and dot segments, unsupported verbs and non-JS options raise" do
    for name <- ["", ".", "..", <<255>>] do
      assert_raise ArgumentError, fn -> event(name) end
    end

    assert_raise ArgumentError, fn -> event("x", verb: :head) end
    assert_raise ArgumentError, fn -> event("x", opts: %{}) end
  end

  test "connect preserves its POST contract and optional search parameters" do
    assert connect() =~ "@post("
    assert connect() =~ "location.pathname"
    assert connect() =~ ", {retryMaxCount: Infinity})"
    assert connect(opts: "{retryMaxCount: 3}") =~ ", {retryMaxCount: 3})"

    assert connect(include_search: true) =~ " + location.search, {retryMaxCount: Infinity})"

    assert_raise ArgumentError, fn -> connect(opts: %{}) end
  end

  test "component patches add change tracking and pass selector options" do
    conn =
      conn(:post, "/")
      |> StarView.SSE.start()
      |> patch(&AssigningComponent.banner/1, [n: 7], selector: "#slot", mode: :inner)

    {200, _headers, body} = TestAssertions.chunked_resp(conn)
    assert body =~ "n=7"
    assert body =~ "data: selector #slot"
    assert body =~ "data: mode inner"
  end

  test "explicit component change metadata is preserved" do
    owner = self()

    component = fn assigns ->
      send(owner, {:metadata, assigns.__changed__})
      {:safe, "<div id='metadata'></div>"}
    end

    conn(:post, "/") |> StarView.SSE.start() |> patch(component, %{__changed__: %{n: true}})
    assert_receive {:metadata, %{n: true}}
  end
end
