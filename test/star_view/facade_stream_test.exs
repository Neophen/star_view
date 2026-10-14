defmodule StarView.FacadeStreamTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias StarView.StreamRegistry
  alias StarView.TestAssertions

  setup do
    start_supervised!(StreamRegistry)
    :ok
  end

  test "start_stream/2 delegates to StreamRegistry and opens SSE" do
    tab_id = "facade-tab"
    query = URI.encode_query(%{"datastar" => ~s({"tabId":"#{tab_id}"})})

    conn =
      :get
      |> conn("/?#{query}")
      |> StarView.start_stream(:user_1)

    assert conn.state == :chunked
    assert {:ok, pid, token} = StreamRegistry.owner({:user_1, tab_id})
    assert is_reference(token)
    assert pid == self()

    assert {200, headers, _body} = TestAssertions.chunked_resp(conn)
    assert {"content-type", "text/event-stream; charset=utf-8"} in headers
  end
end
