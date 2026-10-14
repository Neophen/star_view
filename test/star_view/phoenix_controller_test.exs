defmodule StarView.ControllerTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias StarView.Actions
  alias StarView.Controller
  alias StarView.Dispatch
  alias StarView.TestAssertions
  alias StarView.TestComponents
  alias StarView.TestHandlers.NoAutoRenderController
  alias StarView.TestHandlers.OrderController
  alias StarView.TestHandlers.PageController

  test "tracks initial signals as JSON" do
    conn =
      :get
      |> conn("/")
      |> Controller.signal(:count, 1)
      |> Controller.signal(:name, nil)

    assert StarView.JSON.decode!(Controller.init_signals(conn)) == %{"count" => 1, "name" => nil}
  end

  test "marker dispatch starts SSE, calls handle_event, and patches signals" do
    encoded = Actions.encode_module(PageController)

    conn =
      :post
      |> conn("/ds/#{encoded}/set_count", ~s({"count":5}))
      |> Map.put(:path_params, %{"module" => encoded, "event" => "set_count"})
      |> Dispatch.call([])

    assert {200, _headers, body} = TestAssertions.chunked_resp(conn)

    assert body ==
             """
             event: datastar-patch-signals
             data: signals {"count":5}

             """
  end

  test "signal patches are sent immediately in handler pipeline order" do
    encoded = Actions.encode_module(OrderController)

    conn =
      :post
      |> conn("/ds/#{encoded}/signal_then_patch", ~s({}))
      |> Map.put(:path_params, %{"module" => encoded, "event" => "signal_then_patch"})
      |> Dispatch.call([])

    assert {200, _headers, body} = TestAssertions.chunked_resp(conn)

    assert body ==
             """
             event: datastar-patch-signals
             data: signals {"count":7}

             event: datastar-patch-elements
             data: elements <div id="count">7</div>

             """
  end

  test "use StarView forwards options to controller macro" do
    conn = conn(:get, "/")

    assert NoAutoRenderController.action(conn, []) == conn
  end

  test "patch_element renders function components against assigns" do
    conn =
      :post
      |> conn("/")
      |> StarView.start()
      |> assign(:count, 3)
      |> Controller.patch_element(fn assigns -> ~s(<div id="count">#{assigns.count}</div>) end)

    assert {200, _headers, body} = TestAssertions.chunked_resp(conn)

    assert body ==
             """
             event: datastar-patch-elements
             data: elements <div id="count">3</div>

             """
  end

  test "patch_element supplies HEEx change tracking for components that assign values" do
    conn = conn(:post, "/") |> StarView.start() |> assign(:count, 3)
    conn = Controller.patch_element(conn, &TestComponents.tracked/1)
    assert {200, _headers, body} = TestAssertions.chunked_resp(conn)
    assert body =~ "data: elements <div id=\"tracked\">4</div>"
    refute Map.has_key?(conn.assigns, :__changed__)
  end

  test "patch_element preserves explicit change tracking metadata" do
    conn = conn(:post, "/") |> StarView.start() |> assign(:__changed__, %{existing: true})
    conn = Controller.patch_element(conn, &tracked_metadata/1)
    assert {200, _headers, body} = TestAssertions.chunked_resp(conn)
    assert body =~ "existing=true"
  end

  defp tracked_metadata(assigns) do
    assert assigns.__changed__ == %{existing: true}
    "<div id=\"metadata\">existing=true</div>"
  end
end
