defmodule StarView.ScriptsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarView.Scripts
  alias StarView.TestAssertions

  defp sse_body(conn) do
    {200, _headers, body} = TestAssertions.chunked_resp(conn)
    body
  end

  test "formats execute script as an append-to-body element patch" do
    assert Scripts.format_execute("console.log('hello')", auto_remove: false) ==
             """
             event: datastar-patch-elements
             data: selector body
             data: mode append
             data: elements <script>console.log('hello')</script>

             """
  end

  test "auto-removes scripts by default and escapes closing script tags" do
    assert Scripts.format_execute("document.body.innerHTML = '</script>'") ==
             """
             event: datastar-patch-elements
             data: selector body
             data: mode append
             data: elements <script data-effect="el.remove()">document.body.innerHTML = '<\\/script>'</script>

             """
  end

  test "escapes closing script tags case-insensitively" do
    assert Scripts.format_execute("document.body.innerHTML = '</SCRIPT>'") =~ "<\\/SCRIPT>"

    assert Scripts.format_execute("'</ScRiPt >' + '</SCRIPT/'") =~
             "'<\\/ScRiPt >' + '<\\/SCRIPT/'"
  end

  test "attribute names cannot break out of the script tag" do
    Enum.each(["on>load", ~s|x" onload="evil()|, "a b", "on\tload"], &assert_invalid_attribute/1)
  end

  defp assert_invalid_attribute(name) do
    assert_raise ArgumentError, fn ->
      Scripts.format_execute("1", attributes: %{name => "value"})
    end
  end

  test "bare attributes are names and values use tuple or map attributes" do
    assert_raise ArgumentError, fn ->
      Scripts.format_execute("1", attributes: [~s(type="module")])
    end

    assert Scripts.format_execute("1",
             auto_remove: false,
             attributes: [{"data-on:click", "doIt()"}, {"nonce", "abc"}, "defer"]
           ) =~
             ~s|<script data-on:click="doIt()" nonce="abc" defer>1</script>|
  end

  test "includes custom script attributes when provided" do
    formatted =
      Scripts.format_execute("console.log('x')",
        attributes: %{"type" => "module", "crossorigin" => "anonymous"}
      )

    assert formatted =~ ~s|type="module"|
    assert formatted =~ ~s|crossorigin="anonymous"|
    assert formatted =~ ~s|data-effect="el.remove()"|
  end

  test "redirect/2 emits a deferred navigation script" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.redirect("/workspaces")
      |> sse_body()

    assert body =~ ~s|setTimeout(function(){window.location.href="/workspaces"},0)|
  end

  test "console_log/2 uses console.warn for level :warn" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("hello", level: :warn)
      |> sse_body()

    assert body =~ ~s|console.warn("hello")|
  end

  test "console_log/2 uses console.error for level :error" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("hello", level: :error)
      |> sse_body()

    assert body =~ ~s|console.error("hello")|
  end

  test "console_log/2 uses console.info for level :info" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("hello", level: :info)
      |> sse_body()

    assert body =~ ~s|console.info("hello")|
  end

  test "console_log/2 uses console.debug for level :debug" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("hello", level: :debug)
      |> sse_body()

    assert body =~ ~s|console.debug("hello")|
  end

  test "console_log/2 accepts string level names" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("warned", level: "warn")
      |> sse_body()

    assert body =~ ~s|console.warn("warned")|
  end

  test "console_log/2 falls back to console.log for unknown levels" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log("fallback", level: :trace)
      |> sse_body()

    assert body =~ ~s|console.log("fallback")|
  end

  test "console_log/2 JSON-encodes non-string messages" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.console_log(%{count: 1}, level: :info)
      |> sse_body()

    assert body =~ "console.info("
    assert body =~ ~s|{"count":1}|
  end

  test "execute/2 respects auto_remove: false" do
    body =
      conn(:get, "/")
      |> StarView.start()
      |> Scripts.execute("alert(1)", auto_remove: false)
      |> sse_body()

    assert body =~ "<script>alert(1)</script>"
    refute body =~ "data-effect"
  end
end
