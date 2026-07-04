defmodule Mix.Tasks.StarView.Setup.AuthTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  test "generates the auth pages and routes for Phoenix projects" do
    igniter =
      phx_test_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.setup.auth")

    auth_controller = file_content(igniter, "lib/octafest_web/controllers/auth_controller.ex")

    assert auth_controller =~ "defmodule OctafestWeb.AuthController do"
    assert auth_controller =~ "use OctafestWeb, :star_view"
    assert auth_controller =~ "use AshAuthentication.Phoenix.Controller"
    assert auth_controller =~ "Octafest.Accounts.request_magic_link(email,"
    assert auth_controller =~ "<Layout.auth conn={@conn}>"
    assert auth_controller =~ "clear_session(:octafest)"
    assert auth_controller =~ ~s|post("magic_link")|

    magic_sign_in = file_content(igniter, "lib/octafest_web/controllers/auth/magic_sign_in.ex")

    assert magic_sign_in =~ "defmodule OctafestWeb.Auth.MagicSignIn do"
    assert magic_sign_in =~ "use OctafestWeb, :star_view"
    assert magic_sign_in =~ "alias Octafest.Accounts"
    assert magic_sign_in =~ "alias Octafest.Accounts.User"
    assert magic_sign_in =~ "Accounts.sign_in_with_magic_link(token, %{}"
    assert magic_sign_in =~ "<Layout.auth conn={@conn}>"
    assert magic_sign_in =~ ~s|action={~p"/magic_link/\#{@token}"}|

    router = file_content(igniter, "lib/octafest_web/router.ex")

    assert router =~ ~s|get("/auth/sign-in", AuthController, :mount)|
    assert router =~ ~s|get("/magic_link/:token", Auth.MagicSignIn, :mount)|
    assert router =~ ~s|post("/magic_link/:token", Auth.MagicSignIn, :submit)|
    assert router =~ ~s|post("/ds/:module/:event", StarView.Dispatch, [], alias: false)|
    refute router =~ "sign_out_route"
    assert_before(router, "plug(StarView.Plug.RenameCsrfParam)", "plug(:protect_from_forgery)")

    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")

    assert layout =~ "def auth(assigns) do"
    assert layout =~ "attr(:html_class, :string, default: nil)"

    web_module = file_content(igniter, "lib/octafest_web.ex")

    assert web_module =~ "def star_view() do"
  end

  test "replaces ash sign-in routes and adds a sign_out_route" do
    igniter =
      phx_test_project(app_name: :octafest)
      |> update_file_content("lib/octafest_web/router.ex", fn content ->
        content
        |> String.replace(
          "use OctafestWeb, :router",
          "use OctafestWeb, :router\n  use AshAuthentication.Phoenix.Router"
        )
        |> String.replace(
          "get \"/\", PageController, :home",
          """
          get "/", PageController, :home

              sign_in_route register_path: "/register", reset_path: "/reset"
              magic_sign_in_route(Octafest.Accounts.User, :magic_link)
          """
        )
      end)
      |> Igniter.compose_task("star_view.setup.auth")

    router = file_content(igniter, "lib/octafest_web/router.ex")

    refute router =~ "magic_sign_in_route"
    refute router =~ ~r/(?<![a-z_])sign_in_route/
    assert router =~ ~s|sign_out_route(AuthController)|
    assert router =~ ~s|get("/auth/sign-in", AuthController, :mount)|
    assert router =~ ~s|get("/magic_link/:token", Auth.MagicSignIn, :mount)|
    assert router =~ ~s|post("/magic_link/:token", Auth.MagicSignIn, :submit)|
  end

  test "patches an existing layout without an auth layout" do
    igniter =
      phx_test_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.setup.web_module")
      |> update_file_content(
        "lib/octafest_web/components/star_view/layout.ex",
        fn _content -> legacy_layout() end
      )
      |> Igniter.compose_task("star_view.setup.auth")

    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")

    assert layout =~ "def auth(assigns) do"
    assert layout =~ ~s|html_class="h-full bg-base-200"|
    assert layout =~ "attr(:theme, :string, default: nil)"
    assert layout =~ "attr(:html_class, :string, default: nil)"
    assert layout =~ "attr(:body_class, :string, default: nil)"
    assert layout =~ "<html lang={@lang} class={@html_class} data-theme={@theme}>"
    assert layout =~ "<body {csrf_signal()} {@body_attrs} class={@body_class}>"

    # The auth layout is inserted after `app/1`, so its attrs still belong to
    # `root/1`.
    assert_before(layout, "def app(assigns) do", "def auth(assigns) do")
    assert_before(layout, "def auth(assigns) do", "defp root(assigns) do")
  end

  test "is idempotent when run twice" do
    igniter =
      phx_test_project(app_name: :octafest)
      |> Igniter.compose_task("star_view.setup.auth")
      |> Igniter.compose_task("star_view.setup.auth")

    router = file_content(igniter, "lib/octafest_web/router.ex")
    layout = file_content(igniter, "lib/octafest_web/components/star_view/layout.ex")

    assert count_occurrences(router, ~s|get("/auth/sign-in", AuthController, :mount)|) == 1

    assert count_occurrences(router, ~s|post("/magic_link/:token", Auth.MagicSignIn, :submit)|) ==
             1

    assert count_occurrences(layout, "def auth(assigns) do") == 1
  end

  defp legacy_layout() do
    """
    defmodule OctafestWeb.Components.StarView.Layout do
      use OctafestWeb, :html
      import StarView.Controller, only: [init_signals: 1]

      attr :conn, :map, required: true
      attr :lang, :string, default: "en"
      attr :body_attrs, :map, default: %{}

      slot :inner_block, required: true
      slot :head

      def app(assigns) do
        ~H\"\"\"
        <.root lang={@lang} body_attrs={@body_attrs}>
          <:head :if={@head != []}>{render_slot(@head)}</:head>
          <main data-signals={init_signals(@conn)}>
            {render_slot(@inner_block)}
          </main>
        </.root>
        \"\"\"
      end

      attr :lang, :string, default: "en"
      attr :body_attrs, :map, default: %{}
      slot :inner_block, required: true
      slot :head

      defp root(assigns) do
        ~H\"\"\"
        <!DOCTYPE html>
        <html lang={@lang}>
          <head>
            <meta charset="utf-8" />
            <meta name="csrf-token" content={get_csrf_token()} />
            {render_slot(@head)}
          </head>
          <body {csrf_signal()} {@body_attrs}>
            {render_slot(@inner_block)}
          </body>
        </html>
        \"\"\"
      end

      defp csrf_signal() do
        %{"data-signals:csrf" => "'\#{get_csrf_token()}'"}
      end
    end
    """
  end

  defp file_content(igniter, path) do
    igniter.rewrite
    |> Rewrite.source!(path)
    |> Rewrite.Source.get(:content)
  end

  defp update_file_content(igniter, path, fun) do
    source = Rewrite.source!(igniter.rewrite, path)
    content = Rewrite.Source.get(source, :content)
    source = Igniter.update_source(source, igniter, :content, fun.(content))

    %{igniter | rewrite: Rewrite.update!(igniter.rewrite, source)}
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end

  defp assert_before(source, first, second) do
    {first_index, _} = :binary.match(source, first)
    {second_index, _} = :binary.match(source, second)

    assert first_index < second_index
  end
end
