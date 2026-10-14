defmodule StarView.DispatchTransportTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias StarView.Actions
  alias StarView.AllowlistedTransportHandler
  alias StarView.Dispatch
  alias StarView.SSE.TransportError
  alias StarView.TransportAdapter
  alias StarView.TransportHandler

  test "marker dispatcher gracefully halts only a typed closed transport and preserves assigns" do
    conn = dispatch_conn(TransportHandler, "write", :closed)
    conn = Dispatch.call(conn, [])
    assert conn.state == :chunked
    assert conn.halted
    assert conn.assigns.written
  end

  test "allowlisted dispatcher also gracefully halts closed transport" do
    conn = dispatch_conn(AllowlistedTransportHandler, "write", :closed)
    opts = StarView.Plug.Dispatch.init(modules: [AllowlistedTransportHandler])
    assert StarView.Plug.Dispatch.call(conn, opts).halted
  end

  test "connection reset and broken pipe are normal disconnects" do
    Enum.each([:econnreset, :epipe], &assert_disconnect/1)
  end

  defp assert_disconnect(reason) do
    conn = dispatch_conn(TransportHandler, "write", reason)
    assert Dispatch.call(conn, []).halted
    opts = StarView.Plug.Dispatch.init(modules: [AllowlistedTransportHandler])
    conn = dispatch_conn(AllowlistedTransportHandler, "write", reason)
    assert StarView.Plug.Dispatch.call(conn, opts).halted
  end

  test "non-closed transport errors propagate" do
    capture_log(fn -> assert_non_closed_transport() end)
  end

  defp assert_non_closed_transport() do
    conn = dispatch_conn(TransportHandler, "write", :timeout)
    assert_raise TransportError, fn -> Dispatch.call(conn, []) end
  end

  test "a handler RuntimeError with the old closed error message still propagates" do
    capture_log(fn -> assert_handler_error() end)
  end

  defp assert_handler_error() do
    conn = dispatch_conn(TransportHandler, "raise", :closed)

    assert_raise RuntimeError, "failed to send SSE event: :closed", fn ->
      Dispatch.call(conn, [])
    end
  end

  test "raw body is consumed on the conn passed to the handler" do
    encoded = Actions.encode_module(TransportHandler)
    conn = conn(:post, "/", ~s({"count":3}))
    conn = %{conn | path_params: %{"module" => encoded, "event" => "body"}}
    result = Dispatch.call(conn, [])
    assert result.assigns.unread_body == ""
    assert result.assigns.signals == %{"count" => 3}
    assert result.body_params == %{"count" => 3}
  end

  test "non-object signals are refused before SSE" do
    encoded = Actions.encode_module(TransportHandler)
    conn = conn(:post, "/", %{"_json" => [1]})
    conn = %{conn | path_params: %{"module" => encoded, "event" => "write"}}
    result = Dispatch.call(conn, [])
    assert result.status == 400
    assert result.halted
    assert result.state == :sent
    refute result.assigns[:written]
  end

  test "legacy non-keyword options remain unchanged and do not restrict dispatch" do
    Enum.each([%{}, %{only: []}, :legacy, ["legacy"]], &assert_legacy_options/1)
  end

  test "keyword only options remain validated and deny unlisted marked modules" do
    opts = Dispatch.init(only: [])
    result = Dispatch.call(body_conn(), opts)
    assert result.status == 404
    assert result.state == :sent
    assert_raise ArgumentError, fn -> Dispatch.init(only: ["not-a-module"]) end
    assert_raise ArgumentError, fn -> Dispatch.init(only: :legacy) end
  end

  defp assert_legacy_options(opts) do
    assert Dispatch.init(opts) == opts
    result = Dispatch.call(body_conn(), opts)
    assert result.assigns.signals == %{"count" => 3}
  end

  defp body_conn() do
    conn = conn(:post, "/", ~s({"count":3}))

    %{
      conn
      | path_params: %{"module" => Actions.encode_module(TransportHandler), "event" => "body"}
    }
  end

  defp dispatch_conn(handler, event, reason) do
    conn = conn(:post, "/", %{})

    %{
      conn
      | adapter: {TransportAdapter, {:error, reason}},
        path_params: %{"module" => Actions.encode_module(handler), "event" => event}
    }
  end
end
