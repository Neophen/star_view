defmodule Mix.Tasks.StarView.Setup.Auth.Docs do
  @moduledoc false

  def short_doc(), do: "Generates StarView magic-link auth pages for AshAuthentication"
  def example(), do: "mix star_view.setup.auth"

  def long_doc() do
    """
    #{short_doc()}

    Generates a StarView-powered sign-in page and magic-link landing page,
    wires them into the Phoenix router, and replaces the default
    AshAuthentication sign-in routes (`sign_in_route`/`magic_sign_in_route`)
    with the generated pages.

    ## Example

    ```sh
    #{example()}
    ```

    ## What it does

    * Generates `MyAppWeb.AuthController` — the `/auth/sign-in` page with a
      magic-link email form.
    * Generates `MyAppWeb.Auth.MagicSignIn` — the `/magic_link/:token` landing
      page that exchanges the token via a real form POST.
    * Adds the auth routes to the router and removes `sign_in_route` /
      `magic_sign_in_route` if present.
    * Ensures the generated StarView layout module has a `Layout.auth/1`
      layout.
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.StarView.Setup.Auth do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @auth_layout_section """
    attr :conn, :map, required: true
    attr :lang, :string, default: "en"
    attr :theme, :string, default: nil
    attr :body_attrs, :map, default: %{}

    slot :inner_block, required: true
    slot :head

    @spec auth(map()) :: Phoenix.LiveView.Rendered.t()
    def auth(assigns) do
      ~H\"\"\"
      <.root
        lang={@lang}
        theme={@theme}
        html_class="h-full bg-base-200"
        body_class="h-full"
        body_attrs={@body_attrs}
      >
        <:head :if={@head != []}>{render_slot(@head)}</:head>
        <main data-signals={init_signals(@conn)}>
          {render_slot(@inner_block)}
        </main>
      </.root>
      \"\"\"
    end
    """

    @root_layout_attrs """
    attr :theme, :string, default: nil
    attr :html_class, :string, default: nil
    attr :body_class, :string, default: nil
    """

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :star_view,
        adds_deps: [],
        installs: [],
        example: __MODULE__.Docs.example(),
        only: nil,
        positional: [],
        composes: ["star_view.setup.web_module"],
        schema: [],
        defaults: [],
        aliases: [],
        required: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      endpoint_module = Module.concat(web_module, Endpoint)

      {phoenix?, igniter} = Igniter.Project.Module.module_exists(igniter, endpoint_module)

      if phoenix? do
        igniter
        |> Igniter.compose_task("star_view.setup.web_module")
        |> generate_auth_controller(web_module)
        |> generate_magic_sign_in(web_module)
        |> ensure_auth_layout(web_module)
        |> patch_router(web_module)
        |> add_post_setup_notice(web_module)
      else
        Igniter.add_warning(igniter, "No Phoenix endpoint found. Skipping auth setup.")
      end
    end

    # ==================================================================================
    # Generated controllers

    defp generate_auth_controller(igniter, web_module) do
      controller = Module.concat([web_module, AuthController])

      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, controller)

      if exists? do
        igniter
      else
        template =
          Path.join(:code.priv_dir(:star_view), "templates/auth_controller.ex.eex")
          |> EEx.eval_file(
            web_module: web_module,
            accounts_module: accounts_module(igniter),
            otp_app: Igniter.Project.Application.app_name(igniter)
          )

        Igniter.Project.Module.create_module(igniter, controller, template)
      end
    end

    defp generate_magic_sign_in(igniter, web_module) do
      controller = Module.concat([web_module, Auth, MagicSignIn])
      accounts_module = accounts_module(igniter)

      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, controller)

      if exists? do
        igniter
      else
        template =
          Path.join(:code.priv_dir(:star_view), "templates/magic_sign_in.ex.eex")
          |> EEx.eval_file(
            web_module: web_module,
            accounts_module: accounts_module,
            user_module: Module.concat(accounts_module, User)
          )

        # Keep the magic-link page next to the other Phoenix controllers
        # (`controllers/auth/magic_sign_in.ex`), matching AuthController's location.
        path =
          igniter
          |> Igniter.Project.Module.proper_location(Module.concat(web_module, AuthController))
          |> Path.dirname()
          |> Path.join("auth/magic_sign_in.ex")

        Igniter.Project.Module.create_module(igniter, controller, template, path: path)
      end
    end

    defp accounts_module(igniter) do
      igniter
      |> Igniter.Project.Module.module_name_prefix()
      |> Module.concat(Accounts)
    end

    # ==================================================================================
    # Layout

    defp ensure_auth_layout(igniter, web_module) do
      layout_module = Module.concat([web_module, Components, StarView, Layout])

      case Igniter.Project.Module.find_module(igniter, layout_module) do
        {:ok, {igniter, source, _zipper}} ->
          content = Rewrite.Source.get(source, :content)

          if String.contains?(content, "def auth(") do
            igniter
          else
            igniter
            |> add_auth_layout_function(layout_module)
            |> add_root_layout_attrs(layout_module, content)
            |> patch_root_layout_template(layout_module, source, content)
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find #{inspect(layout_module)}. Skipping the `Layout.auth/1` layout setup."
          )
      end
    end

    defp add_auth_layout_function(igniter, layout_module) do
      Igniter.Project.Module.find_and_update_module!(igniter, layout_module, fn zipper ->
        case Igniter.Code.Function.move_to_def(zipper, :app, 1) do
          {:ok, app_zipper} ->
            {:ok,
             Igniter.Code.Common.add_code(app_zipper, @auth_layout_section, placement: :after)}

          :error ->
            {:ok, Igniter.Code.Common.add_code(zipper, @auth_layout_section, placement: :after)}
        end
      end)
    end

    defp add_root_layout_attrs(igniter, layout_module, content) do
      if String.contains?(content, "attr :html_class") do
        igniter
      else
        Igniter.Project.Module.find_and_update_module!(igniter, layout_module, fn zipper ->
          case Igniter.Code.Function.move_to_defp(zipper, :root, 1) do
            {:ok, root_zipper} ->
              {:ok,
               Igniter.Code.Common.add_code(root_zipper, @root_layout_attrs, placement: :before)}

            :error ->
              {:warning, root_layout_warning(layout_module)}
          end
        end)
      end
    end

    defp patch_root_layout_template(igniter, layout_module, source, content) do
      html_marker = "<html lang={@lang}>"
      body_marker = "<body {csrf_signal()} {@body_attrs}>"

      if String.contains?(content, html_marker) && String.contains?(content, body_marker) do
        path = Rewrite.Source.get(source, :path)

        Igniter.update_file(igniter, path, fn source ->
          Igniter.update_source(source, igniter, :content, fn content ->
            content
            |> String.replace(
              html_marker,
              "<html lang={@lang} class={@html_class} data-theme={@theme}>"
            )
            |> String.replace(
              body_marker,
              "<body {csrf_signal()} {@body_attrs} class={@body_class}>"
            )
          end)
        end)
      else
        Igniter.add_warning(igniter, root_layout_warning(layout_module))
      end
    end

    defp root_layout_warning(layout_module) do
      """
      Could not update the root layout in #{inspect(layout_module)} for `Layout.auth/1`.

      Add `:theme`, `:html_class`, and `:body_class` attrs to the private `root/1`
      component and apply them to the document:

          attr :theme, :string, default: nil
          attr :html_class, :string, default: nil
          attr :body_class, :string, default: nil

          <html lang={@lang} class={@html_class} data-theme={@theme}>
          ...
          <body {csrf_signal()} {@body_attrs} class={@body_class}>
      """
    end

    # ==================================================================================
    # Router

    defp patch_router(igniter, web_module) do
      {igniter, router} =
        Igniter.Libs.Phoenix.select_router(
          igniter,
          "Which Phoenix router should StarView add the auth routes to?"
        )

      if router do
        igniter
        |> remove_ash_sign_in_routes(router)
        |> add_auth_routes(web_module, router)
        |> ensure_csrf_rename_plug(router)
      else
        Igniter.add_warning(igniter, "No Phoenix router found. Skipping auth route setup.")
      end
    end

    defp remove_ash_sign_in_routes(igniter, router) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        zipper =
          zipper
          |> remove_function_calls(:sign_in_route)
          |> remove_function_calls(:magic_sign_in_route)

        {:ok, zipper}
      end)
    end

    defp remove_function_calls(zipper, name) do
      case Igniter.Code.Function.move_to_function_call(zipper, name, [0, 1, 2, 3]) do
        {:ok, call_zipper} ->
          call_zipper
          |> Sourceror.Zipper.remove()
          |> Sourceror.Zipper.top()
          |> remove_function_calls(name)

        :error ->
          zipper
      end
    end

    defp add_auth_routes(igniter, web_module, router) do
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      source_str = Rewrite.Source.get(source, :content)

      if String.contains?(source_str, "/auth/sign-in") do
        igniter
      else
        Igniter.Libs.Phoenix.append_to_scope(
          igniter,
          "/",
          route_contents(source_str),
          with_pipelines: [:browser],
          arg2: web_module,
          router: router
        )
      end
    end

    defp route_contents(source_str) do
      ash_router? = String.contains?(source_str, "AshAuthentication.Phoenix.Router")
      sign_out_route? = String.contains?(source_str, "sign_out_route")
      ds_route? = String.contains?(source_str, ~s("/ds/:module/:event"))

      routes = """
      get "/auth/sign-in", AuthController, :mount
      get "/magic_link/:token", Auth.MagicSignIn, :mount
      post "/magic_link/:token", Auth.MagicSignIn, :submit
      """

      routes =
        if ash_router? && !sign_out_route? do
          routes <> "sign_out_route AuthController\n"
        else
          routes
        end

      if ds_route? do
        routes
      else
        routes <> "post \"/ds/:module/:event\", StarView.Dispatch, [], alias: false\n"
      end
    end

    defp ensure_csrf_rename_plug(igniter, router) do
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      source_str = Rewrite.Source.get(source, :content)

      if String.contains?(source_str, "StarView.Plug.RenameCsrfParam") do
        igniter
      else
        Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
          with {:ok, pipeline} <-
                 Igniter.Code.Function.move_to_function_call(
                   zipper,
                   :pipeline,
                   2,
                   &Igniter.Code.Function.argument_equals?(&1, 0, :browser)
                 ),
               {:ok, pipeline_block} <- Igniter.Code.Common.move_to_do_block(pipeline),
               {:ok, protect_from_forgery} <-
                 Igniter.Code.Function.move_to_function_call_in_current_scope(
                   pipeline_block,
                   :plug,
                   [1, 2],
                   &Igniter.Code.Function.argument_equals?(&1, 0, :protect_from_forgery)
                 ) do
            {:ok,
             Igniter.Code.Common.add_code(
               protect_from_forgery,
               "plug StarView.Plug.RenameCsrfParam",
               placement: :before
             )}
          else
            _ ->
              {:warning,
               """
               Could not add StarView.Plug.RenameCsrfParam to the #{inspect(router)} browser pipeline.
               Add it before `plug :protect_from_forgery` manually.
               """}
          end
        end)
      end
    end

    # ==================================================================================
    # Notices

    defp add_post_setup_notice(igniter, web_module) do
      accounts_module = accounts_module(igniter)

      Igniter.add_notice(igniter, """
      StarView auth pages generated!

        * #{inspect(Module.concat(web_module, AuthController))} — GET /auth/sign-in
        * #{inspect(Module.concat([web_module, Auth, MagicSignIn]))} — GET/POST /magic_link/:token

      The generated pages expect an AshAuthentication magic-link strategy with
      `require_interaction? true` and these code interfaces on #{inspect(accounts_module)}:

        * `request_magic_link/2` — requests a sign-in link for an email
        * `sign_in_with_magic_link/3` — exchanges the token for a signed-in user

      Point your magic-link sender email at:

          url(~p"/magic_link/\#{token}")
      """)
    end
  end
else
  defmodule Mix.Tasks.StarView.Setup.Auth do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"
    @moduledoc __MODULE__.Docs.long_doc()
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("Requires igniter.")
      exit({:shutdown, 1})
    end
  end
end
