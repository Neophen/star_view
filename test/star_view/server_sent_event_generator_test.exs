defmodule StarView.SSETest do
  use ExUnit.Case, async: true

  alias StarView.SSE
  alias StarView.TransportAdapter

  test "formats events in SDK order and omits default retry" do
    assert SSE.format_event(
             "datastar-patch-signals",
             ["signals {\"count\":1}"],
             event_id: "event1",
             retry_duration: 1000
           ) ==
             """
             event: datastar-patch-signals
             id: event1
             data: signals {"count":1}

             """
  end

  test "includes non-default retry duration" do
    assert SSE.format_event(
             "datastar-patch-elements",
             ["elements <div></div>"],
             retry_duration: 2000
           ) ==
             """
             event: datastar-patch-elements
             retry: 2000
             data: elements <div></div>

             """
  end

  test "formatting errors retain ArgumentError rather than becoming transport errors" do
    conn = Plug.Test.conn(:post, "/") |> SSE.start()
    assert_raise ArgumentError, fn -> SSE.send!(conn, "event", [123]) end
    assert_raise ArgumentError, fn -> SSE.send(conn, "event", [123]) end
  end

  test "only adapter write failures become typed transport errors" do
    conn = Plug.Test.conn(:post, "/")
    conn = %{conn | state: :chunked, adapter: {TransportAdapter, {:error, :timeout}}}
    assert SSE.send(conn, "event", "valid") == {:error, :timeout}
    error = assert_raise SSE.TransportError, fn -> SSE.send!(conn, "event", "valid") end
    assert error.reason == :timeout
  end

  test "CR LF and CRLF values cannot inject event id or retry fields" do
    event =
      SSE.format_event("safe\r\nevent: forged", ["first\rsecond\n\nthird\r\nfourth"],
        event_id: "id\r\nretry: 3",
        retry: "2000\r\nid: forged"
      )

    assert length(Regex.scan(~r/^event:/m, event)) == 1
    assert length(Regex.scan(~r/^id:/m, event)) == 1
    assert length(Regex.scan(~r/^retry:/m, event)) == 1
    assert length(Regex.scan(~r/^data:/m, event)) == 5
    assert String.split(event, "\n\n") == [String.trim_trailing(event, "\n"), ""]
    refute event =~ "\r"
  end
end
