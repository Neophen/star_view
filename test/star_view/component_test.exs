defmodule StarView.ComponentTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import StarView.Test

  alias StarView.Actions
  alias StarView.ComponentTest.DetailDrawer
  alias StarView.Dispatch

  test "component event expressions use a validated browser dispatch base and literal segments" do
    html =
      DetailDrawer.drawer(%{__changed__: nil, item: %{id: "abc", title: "T"}})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ "document.body.dataset.dsBase"
    assert html =~ "/#{Actions.encode_module(DetailDrawer)}/change_title%3Aabc"
    assert html =~ "invalid StarView path"
  end

  test "events support every action verb and trusted JS options" do
    assert DetailDrawer.event("remove", verb: :delete) =~ "@delete("
    assert DetailDrawer.event("save", opts: "{retryMaxCount: 5}") =~ ", {retryMaxCount: 5})"
    assert_raise ArgumentError, fn -> DetailDrawer.event("save", verb: :head) end
    assert_raise ArgumentError, fn -> DetailDrawer.event("save", opts: %{}) end
  end

  test "event names are encoded as data, with invalid dot segments rejected" do
    assert DetailDrawer.event("bad/name'č") =~ "bad%2Fname%27%C4%8D"

    for name <- ["", ".", "..", <<255>>] do
      assert_raise ArgumentError, fn -> DetailDrawer.event(name) end
    end
  end

  test "component markers dispatch through the existing dispatcher" do
    encoded = Actions.encode_module(DetailDrawer)

    conn =
      conn(:post, "/ds/#{encoded}/change_title:abc", ~s({"title":"New"}))
      |> Map.put(:path_params, %{"module" => encoded, "event" => "change_title:abc"})
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Dispatch.call([])

    assert DetailDrawer.__star_view_handler__()
    assert conn.state == :chunked
    assert_patched_signals(conn, %{saved: true, title: "New"})
  end
end
