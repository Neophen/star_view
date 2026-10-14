defmodule StarView.TestTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import StarView.Test

  defp sse_conn() do
    :post
    |> conn("/")
    |> StarView.start()
  end

  test "sse_events parses chunked SSE bodies from the test adapter" do
    conn =
      sse_conn()
      |> StarView.patch_signals(%{count: 1})
      |> StarView.patch_elements(~s(<div id="target">Hi</div>))

    assert [
             %{type: "datastar-patch-signals", data: [~s(signals {"count":1})]},
             %{type: "datastar-patch-elements", data: [~s(elements <div id="target">Hi</div>)]}
           ] = sse_events(conn)
  end

  test "sse_events parses raw body strings" do
    body = "event: demo\ndata: one\ndata: two\n\n"

    assert sse_events(body) == [%{type: "demo", data: ["one", "two"]}]
  end

  test "patched_signals deep-merges every signal patch on the conn" do
    conn =
      sse_conn()
      |> StarView.patch_signals(%{count: 1, user: %{name: "Ada"}})
      |> StarView.patch_signals(%{user: %{role: "admin"}})

    assert patched_signals(conn) == %{
             "count" => 1,
             "user" => %{"name" => "Ada", "role" => "admin"}
           }
  end

  test "assert_patched_signals accepts atom or string keys and returns the conn" do
    conn = StarView.patch_signals(sse_conn(), %{count: 2})

    assert %Plug.Conn{} = assert_patched_signals(conn, %{count: 2})
    assert %Plug.Conn{} = assert_patched_signals(conn, %{"count" => 2})
  end

  test "assert_patched_signals fails with a helpful message" do
    conn = StarView.patch_signals(sse_conn(), %{count: 2})

    assert_raise ExUnit.AssertionError, ~r/expected signal "count" to be patched to 3/, fn ->
      assert_patched_signals(conn, %{count: 3})
    end
  end

  test "assert_patched_element matches selector lines and id attributes" do
    by_id = StarView.patch_elements(sse_conn(), ~s(<div id="target">Hi</div>))
    by_selector = StarView.remove_elements(sse_conn(), "#old")

    assert %Plug.Conn{} = assert_patched_element(by_id, "#target")
    assert %Plug.Conn{} = assert_patched_element(by_selector, "#old")
  end

  test "assert_patched_element fails when no event targets the id" do
    conn = StarView.patch_elements(sse_conn(), ~s(<div id="other">Hi</div>))

    assert_raise ExUnit.AssertionError, ~r/no datastar-patch-elements event targeting/, fn ->
      assert_patched_element(conn, "#target")
    end
  end

  test "assert_patched_element rejects non-id targets" do
    assert_raise ArgumentError, ~r/only supports "#id" targets/, fn ->
      assert_patched_element(sse_conn(), "div.card")
    end
  end

  test "multiline signal JSON and null removals remain observable" do
    conn = StarView.Signals.patch_raw(sse_conn(), ~s({\n"user": {"name": "Ada"}\n}))
    conn = StarView.remove_signals(conn, "user.name")
    assert patched_signals(conn) == %{"user" => %{"name" => nil}}
  end

  test "nested expected atom keys compare against JSON keys" do
    conn = StarView.patch_signals(sse_conn(), %{user: %{name: "Ada"}})
    assert assert_patched_signals(conn, %{user: %{name: "Ada"}}) == conn
  end

  test "a missing null-valued signal does not count as a patch" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_patched_signals(sse_conn(), %{absent: nil})
    end
  end

  test "element ids may use single-quoted HTML attributes" do
    conn = StarView.patch_elements(sse_conn(), "<div id='target'>Hi</div>")
    assert assert_patched_element(conn, "#target") == conn
  end
end
