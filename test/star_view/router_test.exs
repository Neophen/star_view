defmodule StarView.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import StarView.Test

  alias StarView.Actions
  alias StarView.RouterTest.CustomBaseRouter
  alias StarView.RouterTest.DefaultBaseRouter
  alias StarView.RouterTest.ScopedRouter
  alias StarView.RouterTest.TestRouter

  @moduletag :capture_log

  defp call(conn), do: TestRouter.call(conn, TestRouter.init([]))

  defp call_scoped(conn), do: ScopedRouter.call(conn, ScopedRouter.init([]))

  test "GET page route renders the page" do
    conn = call(conn(:get, "/counter"))
    assert conn.status == 200
    assert conn.resp_body =~ "counter"
  end

  test "POST event route dispatches handle_event" do
    conn =
      conn(:post, "/counter/_event/increment")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{"count" => 1})
      |> call()

    assert conn.state == :chunked
    assert_patched_signals(conn, %{count: 2})
  end

  test "event route matches other verbs for event/2 verb overrides" do
    conn =
      conn(:delete, "/counter/_event/remove")
      |> call()

    assert conn.state == :chunked
    assert_patched_signals(conn, %{removed: true})
  end

  test "GET/DELETE events deliver signals via the datastar query param" do
    datastar = URI.encode_www_form(~s({"count":41}))

    conn =
      conn(:delete, "/counter/_event/increment?datastar=#{datastar}")
      |> call()

    assert conn.state == :chunked
    assert_patched_signals(conn, %{count: 42})
  end

  test "POST stream route 404s when page has no handle_connect" do
    conn = call(conn(:post, "/counter"))
    assert conn.status == 404
  end

  test "star_view_components wires the marker-based dispatch" do
    encoded = Actions.encode_module(StarView.RouterTest.Drawer)

    conn =
      conn(:post, "/ds/#{encoded}/ping")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{})
      |> call()

    assert conn.state == :chunked
    assert_patched_signals(conn, %{pong: true})
  end

  test "star_view_components defaults to the /ds base, matching the client-side fallback" do
    # Component event/2 falls back to '/ds' when <body data-ds-base> is
    # absent — the macro default must stay in lockstep with it.
    encoded = Actions.encode_module(StarView.RouterTest.Drawer)

    conn =
      conn(:post, "/ds/#{encoded}/ping")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{})
      |> DefaultBaseRouter.call(DefaultBaseRouter.init([]))

    assert conn.state == :chunked
    assert_patched_signals(conn, %{pong: true})
  end

  test "star_view_components routes a custom base" do
    encoded = Actions.encode_module(StarView.RouterTest.Drawer)

    conn =
      conn(:post, "/actions/#{encoded}/ping")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{})
      |> CustomBaseRouter.call(CustomBaseRouter.init([]))

    assert conn.state == :chunked
    assert_patched_signals(conn, %{pong: true})

    assert_raise Phoenix.Router.NoRouteError, fn ->
      conn(:post, "/ds/#{encoded}/ping")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{})
      |> CustomBaseRouter.call(CustomBaseRouter.init([]))
    end
  end

  test "star_view_components rejects modules without the marker" do
    encoded = Actions.encode_module(StarView.RouterTest.TestRouter)

    conn =
      conn(:post, "/ds/#{encoded}/ping")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Map.put(:body_params, %{})
      |> call()

    assert conn.status == 404
  end

  describe "inside an aliased scope" do
    test "GET page route resolves the relative page alias and renders" do
      conn = call_scoped(conn(:get, "/app/counter"))
      assert conn.status == 200
      assert conn.resp_body =~ "counter"
    end

    test "POST event route dispatches without scope-prefixing the plug" do
      conn =
        conn(:post, "/app/counter/_event/increment")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Map.put(:body_params, %{"count" => 4})
        |> call_scoped()

      assert conn.state == :chunked
      assert_patched_signals(conn, %{count: 5})
    end

    test "star_view_components dispatches inside the scope" do
      encoded = Actions.encode_module(StarView.RouterTest.Drawer)

      conn =
        conn(:post, "/app/ds/#{encoded}/ping")
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Map.put(:body_params, %{})
        |> call_scoped()

      assert conn.state == :chunked
      assert_patched_signals(conn, %{pong: true})
    end
  end

  test "__event_path__ handles trailing slashes" do
    assert StarView.Router.__event_path__("/counter") == "/counter/_event/:event"
    assert StarView.Router.__event_path__("/counter/") == "/counter/_event/:event"
  end

  test "__dispatch_path__ handles trailing slashes" do
    assert StarView.Router.__dispatch_path__("/ds") == "/ds/:module/:event"
    assert StarView.Router.__dispatch_path__("/ds/") == "/ds/:module/:event"
  end

  test "default page/component event routes never expose mutations through GET" do
    assert_raise Phoenix.Router.NoRouteError, fn ->
      call(conn(:get, "/counter/_event/increment"))
    end

    encoded = Actions.encode_module(StarView.TransportHandler)
    assert_raise Phoenix.Router.NoRouteError, fn -> call(conn(:get, "/ds/#{encoded}/write")) end
  end

  test "GET is explicitly routed for read-only pages and only listed marked components" do
    router = StarView.RouterTest.ReadRouter
    result = router.call(conn(:get, "/reader/_event/read"), router.init([]))
    assert_patched_signals(result, %{read: true})
    encoded = Actions.encode_module(StarView.RouterTest.Drawer)
    result = router.call(conn(:get, "/ds/#{encoded}/ping"), router.init([]))
    assert_patched_signals(result, %{pong: true})
    legacy = Actions.encode_module(StarView.TransportHandler)
    result = router.call(conn(:get, "/ds/#{legacy}/write"), router.init([]))
    assert result.status == 404
    refute Map.has_key?(result.assigns, :written)
  end

  test "GET module lists follow the same scoped alias rules as pages" do
    router = StarView.RouterTest.ScopedReadRouter
    result = router.call(conn(:get, "/app/reader/_event/read"), router.init([]))
    assert_patched_signals(result, %{read: true})
    encoded = Actions.encode_module(StarView.RouterTest.Drawer)
    result = router.call(conn(:get, "/app/ds/#{encoded}/ping"), router.init([]))
    assert_patched_signals(result, %{pong: true})
    legacy = Actions.encode_module(StarView.TransportHandler)
    assert router.call(conn(:get, "/app/ds/#{legacy}/write"), router.init([])).status == 404
  end

  test "nonliteral router options fail with a clear error before emitting routes" do
    assert_raise ArgumentError, ~r/router options must be a literal keyword list/, fn ->
      Code.eval_quoted(
        quote do
          require StarView.Router

          StarView.Router.star_view("/invalid", StarView.RouterTest.ReadPage, @options)
        end
      )
    end

    assert_raise ArgumentError, ~r/event_methods must be a literal list/, fn ->
      Code.eval_quoted(
        quote do
          require StarView.Router

          StarView.Router.star_view("/invalid", StarView.RouterTest.ReadPage,
            event_methods: ~w(post delete)a
          )
        end
      )
    end
  end
end
