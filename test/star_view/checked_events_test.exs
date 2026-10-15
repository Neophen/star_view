defmodule StarView.CheckedEventsTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarView.Actions
  alias StarView.CheckedEventsTest.Component
  alias StarView.CheckedEventsTest.Controller
  alias StarView.CheckedEventsTest.Legacy
  alias StarView.CheckedEventsTest.Page
  alias StarView.Dispatch
  alias StarView.Page.Plug, as: PagePlug
  alias StarView.Template
  alias StarView.TestAssertions

  # A body the signal parser would reject with 400. Rejections that come back
  # as 404/405 prove the event check ran before the body was read.
  @malformed "{"

  describe "event contract derived from handle_event/3" do
    test "a display-only checked component can have an empty event contract" do
      source = """
      defmodule StarView.CheckedEventsTest.Compiled.DisplayOnly do
        use StarView.Component, checked_events: true
        import StarView.Template.Sigils
        def render(assigns), do: ~STAR'<p id="static">Static</p>'
      end
      """

      [{module, _binary}] = Code.compile_string(source, "display_only.exs")
      assert module.__star_view_events__() == %{}
      assert Template.to_html(module.render(%{})) == ~s(<p id="static">Static</p>)
      result = dispatch(module, :post, "missing")
      assert result.status == 404
      assert result.state == :sent
    end

    test "registers each literal name with its literal methods, not the fallback" do
      assert Controller.__star_view_events__() == %{
               "read" => ["GET"],
               "remove" => ["DELETE", "PATCH"],
               "save" => ["POST"]
             }
    end

    test "a final override replaces the overridable clauses it hides" do
      [{module, _binary}] = Code.compile_string(final_override_source(), "final_override.exs")

      assert module.__star_view_events__() == %{"new" => ["POST"]}

      assert_rejected(dispatch(module, :post, "old"), 404)
      assert_sse(dispatch(module, :post, "new"))
      assert_handled(module, :new)
    end

    test "an inherited overridable handler registers its effective implementation" do
      source = """
      defmodule StarView.CheckedEventsTest.Compiled.Unresolved do
        use StarView, checked_events: true, auto_render: false
        use StarView.CheckedEventsTest.OverridableBase
        def mount(conn, _params), do: conn
        def render(assigns), do: assigns
      end
      """

      [{module, _binary}] = Code.compile_string(source, "inherited.exs")
      assert module.__star_view_events__() == %{"old" => ["POST"]}
      assert_sse(dispatch(module, :post, "old"))
      assert_handled(module, :old)
    end

    test "a later before_compile hook cannot add an unregistered handler clause" do
      source = """
      defmodule StarView.CheckedEventsTest.Compiled.LateHook do
        use StarView, checked_events: true, auto_render: false
        use Phoenix.Component
        @before_compile StarView.CheckedEventsTest.LateHandler

        def handle_event("save", _signals, %{method: "POST"} = conn), do: conn
      end
      """

      error = compile_error(source, "late_hook.exs")
      assert error.description =~ "before_compile"
    end

    test "a later before_compile hook cannot delete the registered handler" do
      source = """
      defmodule StarView.CheckedEventsTest.Compiled.DeletedHandler do
        use StarView, checked_events: true, auto_render: false
        @before_compile StarView.CheckedEventsTest.DeleteHandler

        def handle_event("save", _signals, %{method: "POST"} = conn), do: conn
      end
      """

      compile_error(source, "deleted_handler.exs")
    end

    test "checked_events must be a literal boolean" do
      source = """
      defmodule StarView.CheckedEventsTest.Compiled.BadOption do
        use StarView, checked_events: :yes, auto_render: false
      end
      """

      assert_raise ArgumentError, ~r/checked_events/, fn ->
        Code.compile_string(source, "bad_option.exs")
      end
    end
  end

  describe "handler clause rules" do
    test "event-name patterns are rejected in favour of signals" do
      clause = ~s|def handle_event("row:" <> _id, _signals, %{method: "POST"} = conn), do: conn|
      source = handler_source("PrefixName", clause)

      assert_compile_error(source, "prefix_name.exs", "literal event names", "row:")
    end

    test "a method checked only in a guard is rejected" do
      clause =
        ~s|def handle_event("save", _signals, conn) when conn.method == "POST", do: conn|

      source = handler_source("GuardMethod", clause)

      assert_compile_error(source, "guard_method.exs", "literal method", "when conn.method")
    end

    test "a method outside GET, POST, PUT, PATCH and DELETE is rejected" do
      clause = ~s|def handle_event("save", _signals, %{method: "OPTIONS"} = conn), do: conn|
      source = handler_source("OptionsMethod", clause)

      assert_compile_error(source, "options_method.exs", "literal method", "OPTIONS")
    end
  end

  describe "~STAR event references" do
    test "render the existing Datastar action syntax" do
      html = %{} |> Controller.render() |> Template.to_html()

      assert html =~ "@post("
      assert html =~ "checked_events_test-controller/save"
      assert html =~ "@delete("
    end

    test "a misspelled controller event fails at the template line" do
      source = controller_source("Typo", ~s|post("svae")|)

      assert_compile_error(source, "typo.exs", ~s|unknown checked event "svae"|, ~s|post("svae")|)
    end

    test "a controller helper with the wrong method fails at the template line" do
      source = controller_source("WrongVerb", ~s|delete("save")|)

      assert_compile_error(source, "wrong_verb.exs", "POST", ~s|delete("save")|)
    end

    test "a dynamic event name fails at the template line" do
      source = controller_source("DynamicName", "post(@event)")

      assert_compile_error(source, "dynamic_name.exs", "literal", "post(@event)")
    end

    test "a dynamic page event verb fails at the template line" do
      source = page_source("DynamicVerb", ~s|event("save", verb: @verb)|)

      assert_compile_error(source, "dynamic_verb.exs", "verb", "verb: @verb")
    end

    test "a page event with the wrong verb fails at the template line" do
      source = page_source("PageWrongVerb", ~s|event("save", verb: :get)|)

      assert_compile_error(source, "page_wrong_verb.exs", "POST", "verb: :get")
    end
  end

  describe "controller dispatch" do
    test "a registered event starts SSE and runs the handler" do
      conn = dispatch(Controller, :post, "save", ~s({"count":1}))

      assert_sse(conn)
      StarView.Test.assert_patched_signals(conn, %{count: 2})
      assert_handled(Controller, {:saved, 1})
    end

    test "a failing input guard falls through to the next clause for the same event" do
      conn = dispatch(Controller, :post, "save", ~s({"count":"one"}))

      assert_sse(conn)
      assert_handled(Controller, :invalid_save)
    end

    test "an unknown event is rejected before reading signals, despite a fallback clause" do
      conn = dispatch(Controller, :post, "missing", @malformed)

      assert_rejected(conn, 404)
    end

    test "a known event with the wrong method is rejected with an Allow header" do
      conn = dispatch(Controller, :put, "save", @malformed)

      assert_rejected(conn, 405)
      assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]
    end

    test "one event can be handled through several methods" do
      assert_sse(dispatch(Controller, :delete, "remove"))
      assert_handled(Controller, :removed)

      assert_sse(dispatch(Controller, :patch, "remove"))
      assert_handled(Controller, :archived)

      conn = dispatch(Controller, :post, "remove", @malformed)
      assert_rejected(conn, 405)
      assert Plug.Conn.get_resp_header(conn, "allow") == ["DELETE, PATCH"]
    end
  end

  describe "page and component entrypoints" do
    test "page events dispatch through the page plug" do
      conn = page_event(:post, "save")

      assert_sse(conn)
      StarView.Test.assert_patched_signals(conn, %{saved: true})
      assert_handled(Page, :saved)

      assert_sse(page_event(:get, "read"))
      assert_handled(Page, :read)
    end

    test "page events reject unknown names and wrong methods before reading signals" do
      assert_rejected(page_event(:post, "missing", @malformed), 404)

      conn = page_event(:put, "save", @malformed)
      assert_rejected(conn, 405)
      assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]
    end

    test "component events dispatch and reject unknown names" do
      assert_sse(dispatch(Component, :post, "toggle"))
      assert_handled(Component, :toggled)

      assert_rejected(dispatch(Component, :post, "missing", @malformed), 404)
    end
  end

  describe "unchecked modules" do
    test "keep broad event dispatch and have no event contract" do
      refute function_exported?(Legacy, :__star_view_events__, 0)

      assert_sse(dispatch(Legacy, :put, "anything"))
      assert_handled(Legacy, {"anything", "PUT"})
    end
  end

  # Requests

  defp dispatch(module, method, event, body \\ "{}") do
    encoded = Actions.encode_module(module)

    method
    |> conn("/ds/#{encoded}/#{event}", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Map.put(:path_params, %{"module" => encoded, "event" => event})
    |> Dispatch.call(Dispatch.init([]))
  end

  defp page_event(method, event, body \\ "{}") do
    method
    |> conn("/checked/_event/#{event}", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Map.put(:path_params, %{"event" => event})
    |> PagePlug.call(PagePlug.init({:event, Page}))
  end

  # Assertions

  defp assert_sse(conn) do
    assert {200, headers, _body} = TestAssertions.chunked_resp(conn)
    assert {"content-type", "text/event-stream; charset=utf-8"} in headers
  end

  defp assert_rejected(conn, status) do
    assert conn.halted
    assert conn.state == :sent
    assert conn.status == status
    refute_received {:checked_event, _module, _message}
  end

  defp assert_handled(module, message), do: assert_received({:checked_event, ^module, ^message})

  defp assert_compile_error(source, file, description, needle) do
    error = compile_error(source, file)

    assert error.description =~ description
    assert Path.basename(error.file) == file
    assert error.line == line_of(source, needle)
  end

  defp compile_error(source, file),
    do: assert_raise(CompileError, fn -> Code.compile_string(source, file) end)

  defp line_of(source, needle) do
    index = source |> String.split("\n") |> Enum.find_index(&String.contains?(&1, needle))
    index + 1
  end

  # Sources. Module names are fixed test literals, never request data.

  defp controller_source(name, call) do
    """
    defmodule StarView.CheckedEventsTest.Compiled.#{name} do
      use StarView, checked_events: true, auto_render: false
      use Phoenix.Component

      import StarView.Template.Sigils

      def render(assigns) do
        ~STAR\"""
        <button data-on:click={#{call}}>Go</button>
        \"""
      end

      def handle_event("save", _signals, %{method: "POST"} = conn), do: conn
    end
    """
  end

  defp page_source(name, call) do
    """
    defmodule StarView.CheckedEventsTest.Compiled.#{name} do
      use StarView.Page, checked_events: true

      import StarView.Template.Sigils

      def render(assigns) do
        ~STAR\"""
        <button data-on:click={#{call}}>Go</button>
        \"""
      end

      def handle_event("save", _signals, %{method: "POST"} = conn), do: conn
    end
    """
  end

  defp handler_source(name, clause) do
    """
    defmodule StarView.CheckedEventsTest.Compiled.#{name} do
      use StarView, checked_events: true, auto_render: false

      #{clause}
    end
    """
  end

  defp final_override_source() do
    """
    defmodule StarView.CheckedEventsTest.Compiled.FinalOverride do
      use StarView, checked_events: true, auto_render: false
      use StarView.CheckedEventsTest.OverridableBase
      def mount(conn, _params), do: conn
      def render(assigns), do: assigns

      def handle_event("new", _signals, %{method: "POST"} = conn) do
        send(self(), {:checked_event, __MODULE__, :new})
        conn
      end
    end
    """
  end
end
