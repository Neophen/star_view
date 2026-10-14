defmodule StarView.SignalsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarView.Signals

  test "formats a signal patch" do
    assert Signals.format_patch(%{"count" => 1}, only_if_missing: true) ==
             """
             event: datastar-patch-signals
             data: onlyIfMissing true
             data: signals {"count":1}

             """
  end

  test "formats raw multiline signal JSON" do
    assert Signals.format_patch_raw("{\n  \"count\": 1\n}") ==
             """
             event: datastar-patch-signals
             data: signals {
             data: signals   "count": 1
             data: signals }

             """
  end

  test "CR-only JSON lines retain their Datastar signals prefix" do
    assert Signals.format_patch_raw("{\r\"count\":1\r}") ==
             "event: datastar-patch-signals\ndata: signals {\ndata: signals \"count\":1\ndata: signals }\n\n"
  end

  test "formats signal removals as JSON null patches" do
    assert Signals.format_remove(["user.name", "user.email"]) ==
             """
             event: datastar-patch-signals
             data: signals {"user":{"email":null,"name":null}}

             """
  end

  test "formats parent signal removals consistently with nested paths" do
    assert Signals.format_remove(["user.name", "user"]) ==
             """
             event: datastar-patch-signals
             data: signals {"user":null}

             """

    assert Signals.format_remove(["user", "user.name"]) ==
             """
             event: datastar-patch-signals
             data: signals {"user":null}

             """
  end

  test "reads GET signals from datastar query parameter" do
    conn = conn(:get, "/?datastar=%7B%22count%22%3A1%2C%22gone%22%3Anull%7D")

    assert Signals.read(conn) == {:ok, %{"count" => 1, "gone" => nil}}
  end

  test "reads raw JSON body for non-GET requests" do
    conn = conn(:post, "/", ~s({"count":1}))

    assert Signals.read(conn) == {:ok, %{"count" => 1}}
  end

  test "returns errors for invalid signal JSON" do
    conn = conn(:post, "/", "{")

    assert {:error, _reason} = Signals.read(conn)
  end

  test "rejects non-map signal payloads" do
    conn = conn(:get, "/?datastar=%5B1%5D")

    assert Signals.read(conn) == {:error, {:invalid_signals, [1]}}
  end

  test "fetch returns consumed body state and makes repeated reads safe" do
    original = conn(:post, "/", ~s({"count":1}))
    assert {:ok, %{"count" => 1}, fetched} = Signals.fetch(original)
    assert {:ok, "", _conn} = Plug.Conn.read_body(fetched)
    assert fetched.body_params == %{"count" => 1}
    assert fetched.params == %{"count" => 1}
    refute is_struct(fetched.params)
    assert Signals.read(fetched) == {:ok, %{"count" => 1}}
  end

  test "fetching query params later preserves raw body precedence" do
    original = conn(:post, "/?count=2&query=yes", ~s({"count":1}))
    assert {:ok, _signals, fetched} = Signals.fetch(original)
    fetched = Plug.Conn.fetch_query_params(fetched)
    assert fetched.params == %{"count" => 1, "query" => "yes"}
  end

  test "fetched params retain path over body over query precedence" do
    original = conn(:post, "/?id=query&count=query", ~s({"id":"body","count":"body"}))
    original = %{original | path_params: %{"id" => "route"}}
    assert {:ok, %{"id" => "body", "count" => "body"}, fetched} = Signals.fetch(original)
    fetched = Plug.Conn.fetch_query_params(fetched)
    assert fetched.params == %{"id" => "route", "count" => "body"}
  end

  test "fetch enforces configurable limits for raw body and query JSON" do
    assert {:error, :body_too_large, _conn} =
             Signals.fetch(conn(:post, "/", ~s({"count":1})), max_bytes: 2)

    query = URI.encode_query(%{"datastar" => ~s({"count":1})})

    assert {:error, :body_too_large, _conn} =
             Signals.fetch(conn(:get, "/?#{query}"), max_bytes: 2)
  end

  test "fetch rejects parsed non-object JSON and explicitly empty query input" do
    assert {:error, {:invalid_signals, [1]}, _conn} =
             Signals.fetch(conn(:post, "/", %{"_json" => [1]}))

    assert {:error, :invalid_signals, _conn} = Signals.fetch(conn(:get, "/?datastar="))
  end

  test "fetch preserves query parsing without turning query signals into body params" do
    query = URI.encode_query(%{"datastar" => ~s({"count":1})})
    original = conn(:get, "/?#{query}")
    assert {:ok, %{"count" => 1}, fetched} = Signals.fetch(original)
    assert fetched.query_params["datastar"] == ~s({"count":1})
    assert fetched.body_params == original.body_params
  end

  test "input errors use plain HTTP statuses before SSE" do
    too_large = Signals.send_error(conn(:post, "/"), :body_too_large)
    assert too_large.status == 413
    assert too_large.halted
    invalid = Signals.send_error(conn(:post, "/"), :malformed)
    assert invalid.status == 400
    assert invalid.halted
  end
end
