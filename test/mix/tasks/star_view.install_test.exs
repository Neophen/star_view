defmodule Mix.Tasks.StarView.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "composes setup subtasks when options are enabled" do
    igniter =
      test_project()
      |> Igniter.compose_task("star_view.install", [])

    assert Enum.any?(igniter.notices, &String.contains?(&1, "dispatch plug"))
  end

  test "configures Phoenix endpoint URL and StarView dev URL" do
    igniter =
      phoenix_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.install", ["--no-stream-dedup", "--no-example"])

    content = file_content(igniter, "config/dev.exs")

    assert content =~ """
             url: [
               scheme: "https",
               host: "octafest.test",
               port: 4001
             ],
             https: [
               port: 4001,
               cipher_suite: :strong,
               keyfile: "priv/cert/selfsigned_key.pem",
               certfile: "priv/cert/selfsigned.pem"
             ]
           """

    assert content =~ ~s(star_view: [dev_url: "https://octafest.test:4001"])

    assert Enum.any?(
             igniter.notices,
             &String.contains?(&1, "StarView dev URL configured: https://octafest.test:4001")
           )

    refute_delayed_task(igniter, "phx.gen.cert", ["octafest.test", "localhost"])

    refute_delayed_task(igniter, "star_view.trust", ["--host", "octafest.test"])

    assert Enum.any?(
             igniter.notices,
             &String.contains?(&1, "mix star_view.trust --host octafest.test")
           )

    assert Enum.any?(
             igniter.notices,
             &String.contains?(&1, "brew install mkcert nss")
           )
  end

  test "hyphenates generated development hostnames" do
    igniter =
      phoenix_project(app_name: :star_view_demo)
      |> Igniter.compose_task("star_view.install", ["--no-stream-dedup", "--no-example"])

    content = file_content(igniter, "config/dev.exs")

    assert content =~ ~s(host: "star-view-demo.test")
    assert content =~ ~s(star_view: [dev_url: "https://star-view-demo.test:4001"])
    refute content =~ "star_view_demo.test"

    refute_delayed_task(igniter, "phx.gen.cert", ["star-view-demo.test", "localhost"])
    refute_delayed_task(igniter, "star_view.trust", ["--host", "star-view-demo.test"])

    assert Enum.any?(
             igniter.notices,
             &String.contains?(&1, "mix star_view.trust --host star-view-demo.test")
           )

    assert Enum.any?(
             igniter.warnings,
             &String.contains?(&1, "works more reliably with mkcert")
           )
  end

  test "generates the Phoenix search controller example" do
    igniter =
      phoenix_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.install", ["--no-stream-dedup"])

    content = file_content(igniter, "lib/octafest_web/controllers/search_controller.ex")

    assert content =~ "defmodule OctafestWeb.SearchController do"
    assert content =~ "use OctafestWeb, :star_view"
    assert content =~ "def mount(conn, _params) do"

    web_module = file_content(igniter, "lib/octafest_web.ex")

    assert web_module =~ "def star_view do"
    assert web_module =~ "use Phoenix.Controller, formats: [:html, :json]"
    assert web_module =~ "use StarView"
    assert web_module =~ "use Phoenix.Component"
    assert web_module =~ "use Gettext, backend: OctafestWeb.Gettext"
    assert web_module =~ "import Phoenix.Component, except: [assign: 3]"
    assert web_module =~ "alias OctafestWeb.Components.StarView.Layout"
    assert web_module =~ ~r/plug[( ]:put_root_layout, false\)?/
    assert web_module =~ "unquote(verified_routes())"
    assert_top_level_function_order(web_module, [:controller, :star_view, :live_view])
    refute_function_contains_def(web_module, :controller, :star_view)

    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")

    assert layout =~ "defmodule OctafestWeb.Components.StarView.Layout do"
    assert layout =~ "use OctafestWeb, :html"
    assert layout =~ "import StarView.Controller, only: [init_signals: 1]"
    assert layout =~ "def app(assigns) do"
    assert layout =~ "defp root(assigns) do"
    assert layout =~ "data-signals:csrf"

    assert content =~ "<Layout.app conn={@conn}>"
    assert content =~ "</Layout.app>"

    router = file_content(igniter, "lib/octafest_web/router.ex")
    assert_before(router, "plug StarView.Plug.RenameCsrfParam", "plug(:protect_from_forgery)")
    assert router =~ ~s|get "/search", SearchController, :mount|
    assert router =~ ~s|post "/ds/:module/:event", StarView.Dispatch, [], alias: false|
    refute router =~ "Elixir.StarView.Dispatch"
    refute router =~ "OctafestWeb.OctafestWeb.SearchController"
    refute router =~ "OctafestWeb.StarView.Dispatch"
  end

  test "no-example still configures dispatch and CSRF without a sample controller" do
    igniter =
      phoenix_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.install", [
        "--no-stream-dedup",
        "--no-https",
        "--no-example"
      ])

    router = file_content(igniter, "lib/octafest_web/router.ex")
    assert router =~ ~s|post "/ds/:module/:event", StarView.Dispatch, [], alias: false|
    assert_before(router, "plug StarView.Plug.RenameCsrfParam", "plug(:protect_from_forgery)")
    refute router =~ ~s|"/search"|

    refute Map.has_key?(
             igniter.rewrite.sources,
             "lib/octafest_web/controllers/search_controller.ex"
           )

    assert igniter.issues == []
    assert Enum.any?(igniter.notices, &String.contains?(&1, "POST dispatch routing"))
  end

  test "dispatch setup can run independently and leaves existing routes intact on rerun" do
    igniter =
      phoenix_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.setup.dispatch")
      |> Igniter.compose_task("star_view.setup.search_controller")

    router = file_content(igniter, "lib/octafest_web/router.ex")
    assert length(Regex.scan(~r{/ds/:module/:event}, router)) == 1
    assert length(Regex.scan(~r{StarView.Plug.RenameCsrfParam}, router)) == 1
    assert length(Regex.scan(~r{get "/search"}, router)) == 1
    assert igniter.issues == []
  end

  test "an existing GET dispatch route or comment does not suppress POST setup" do
    igniter =
      phoenix_project(app_name: :octafest)
      |> Igniter.Libs.Phoenix.append_to_scope(
        "/",
        """
        # post "/ds/:module/:event", StarView.Dispatch, [], alias: false
        get "/ds/:module/:event", StarView.Dispatch, [], alias: false
        """,
        with_pipelines: [:browser],
        arg2: OctafestWeb,
        router: OctafestWeb.Router
      )
      |> Igniter.compose_task("star_view.setup.dispatch")

    router = file_content(igniter, "lib/octafest_web/router.ex")
    calls = route_calls(router)
    assert Enum.count(calls, &match?({:post, _meta, ["/ds/:module/:event" | _args]}, &1)) == 1
    assert Enum.count(calls, &match?({:get, _meta, ["/ds/:module/:event" | _args]}, &1)) == 1
    assert igniter.issues == []
  end

  test "updates an existing star_view section with layout wiring" do
    old_star_view = """

      def star_view do
        quote do
          use Phoenix.Controller, formats: [:html, :json]
          use StarView
          use Phoenix.Component

          use Gettext, backend: OctafestWeb.Gettext

          import Phoenix.Component, except: [assign: 3]
          import Plug.Conn

          unquote(verified_routes())
        end
      end
    """

    igniter =
      phoenix_project(app_name: :octafest)
      |> update_file_content("lib/octafest_web.ex", fn content ->
        String.replace(content, "\n  def live_view do", old_star_view <> "\n  def live_view do")
      end)
      |> Igniter.compose_task("star_view.setup.web_module")

    web_module = file_content(igniter, "lib/octafest_web.ex")
    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")

    assert web_module =~ "alias OctafestWeb.Components.StarView.Layout"
    assert web_module =~ ~r/plug[( ]:put_root_layout, false\)?/
    refute_function_contains_def(web_module, :star_view, :star_view)
    assert layout =~ "defmodule OctafestWeb.Components.StarView.Layout do"
  end

  defp phoenix_project(opts) do
    # Igniter's applied virtual fixtures load lazily; make router discovery
    # start from the same complete source set as a new Phoenix project.
    opts |> phx_test_project() |> load_fixture_files()
  end

  defp load_fixture_files(igniter) do
    Enum.reduce(
      Map.keys(igniter.assigns.test_files),
      igniter,
      &Igniter.include_existing_file(&2, &1)
    )
  end

  defp file_content(igniter, path) do
    igniter = Igniter.include_existing_file(igniter, path)

    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp update_file_content(igniter, path, fun) do
    igniter = Igniter.include_existing_file(igniter, path)
    source = Rewrite.source!(igniter.rewrite, path)
    content = Rewrite.Source.get(source, :content)
    source = Igniter.update_source(source, igniter, :content, fun.(content))

    %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
  end

  defp refute_delayed_task(igniter, task, argv) do
    refute {task, argv, :delayed} in igniter.tasks
  end

  defp assert_before(source, first, second) do
    {first_index, _} = :binary.match(source, first)
    {second_index, _} = :binary.match(source, second)

    assert first_index < second_index
  end

  defp route_calls(source) do
    source
    |> Code.string_to_quoted!()
    |> Macro.prewalk([], &collect_route_calls/2)
    |> elem(1)
  end

  defp collect_route_calls({verb, _meta, _args} = node, calls) when verb in [:post, :get],
    do: {node, [node | calls]}

  defp collect_route_calls(node, calls), do: {node, calls}

  defp assert_top_level_function_order(source, expected_order) do
    defs =
      source
      |> top_level_functions()
      |> Enum.filter(&(&1 in expected_order))

    assert defs == expected_order
  end

  defp refute_function_contains_def(source, outer_function, inner_function) do
    {_module, body} = module_body(source)

    {_def, _meta, [{^outer_function, _fun_meta, _args}, [do: outer_body]]} =
      Enum.find(body, &function_def?(&1, outer_function))

    refute contains_function_def?(outer_body, inner_function)
  end

  defp top_level_functions(source) do
    {_module, body} = module_body(source)

    body
    |> Enum.filter(&match?({:def, _meta, [_head, _body]}, &1))
    |> Enum.map(fn {:def, _meta, [{name, _fun_meta, _args}, _body]} -> name end)
  end

  defp module_body(source) do
    {:defmodule, _meta, [{:__aliases__, _alias_meta, module}, [do: body]]} =
      Code.string_to_quoted!(source)

    statements =
      case body do
        {:__block__, _meta, statements} -> statements
        statement -> [statement]
      end

    {module, statements}
  end

  defp function_def?({:def, _meta, [{name, _fun_meta, _args}, _body]}, name), do: true
  defp function_def?(_node, _name), do: false

  defp contains_function_def?(node, function_name) do
    {_node, found?} =
      Macro.prewalk(node, false, fn
        {:def, _meta, [{^function_name, _fun_meta, _args}, _body]} = node, _found? ->
          {node, true}

        node, found? ->
          {node, found?}
      end)

    found?
  end
end
