if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.StarView.Setup.StreamPage do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()
    use Igniter.Mix.Task

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

      setup_page(igniter, web_module, phoenix?)
    end

    defp setup_page(igniter, _web_module, false) do
      Igniter.add_warning(igniter, "No Phoenix endpoint found. Skipping stream page setup.")
    end

    defp setup_page(igniter, web_module, true) do
      context = context(igniter, web_module)

      igniter
      |> Igniter.compose_task("star_view.setup.web_module")
      |> generate_ticker(context)
      |> generate_page(context)
      |> add_ticker_to_supervision_tree(context)
      |> patch_router(context)
      |> add_post_setup_notice(context)
    end

    defp context(igniter, web_module) do
      app_module = Igniter.Project.Module.module_name_prefix(igniter)

      %{
        web_module: web_module,
        page_module: Module.concat(web_module, StreamDemoPage),
        layout_module: Module.concat([web_module, Components, StarView, Layout]),
        ticker_module: Module.concat(app_module, DemoTicker),
        pubsub_module: Module.concat(app_module, PubSub)
      }
    end

    # ==================================================================================
    # Generated modules

    defp generate_ticker(igniter, context) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, context.ticker_module)

      if exists? do
        igniter
      else
        template =
          Path.join(:code.priv_dir(:star_view), "templates/demo_ticker.ex.eex")
          |> EEx.eval_file(pubsub_module: context.pubsub_module)

        Igniter.Project.Module.create_module(igniter, context.ticker_module, template)
      end
    end

    defp generate_page(igniter, context) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, context.page_module)

      if exists? do
        igniter
      else
        template =
          Path.join(:code.priv_dir(:star_view), "templates/stream_demo_page.ex.eex")
          |> EEx.eval_file(
            layout_module: context.layout_module,
            ticker_module: context.ticker_module,
            pubsub_module: context.pubsub_module
          )

        Igniter.Project.Module.create_module(igniter, context.page_module, template)
      end
    end

    defp add_ticker_to_supervision_tree(igniter, context) do
      # The ticker broadcasts over PubSub, so it must start after it.
      Igniter.Project.Application.add_new_child(igniter, context.ticker_module,
        after: [Phoenix.PubSub]
      )
    end

    # ==================================================================================
    # Router

    defp patch_router(igniter, context) do
      {igniter, router} = Mix.Tasks.StarView.Setup.Dispatch.select_router(igniter)

      if router do
        igniter
        |> ensure_router_import(router)
        |> add_route(context, router)
        |> Mix.Tasks.StarView.Setup.Dispatch.ensure_csrf_rename_plug(router)
      else
        Igniter.add_warning(igniter, "No Phoenix router found. Skipping stream demo route.")
      end
    end

    defp ensure_router_import(igniter, router) do
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      source_str = Rewrite.Source.get(source, :content)

      if source_contains?(source_str, :router_import) do
        igniter
      else
        Igniter.Project.Module.find_and_update_module!(igniter, router, &insert_router_import/1)
      end
    end

    defp insert_router_import(zipper) do
      case Igniter.Code.Function.move_to_function_call(zipper, :use, 2) do
        {:ok, use_zipper} ->
          {:ok,
           Igniter.Code.Common.add_code(use_zipper, "import StarView.Router", placement: :after)}

        :error ->
          {:warning, "Add `import StarView.Router` manually below your router's use statement."}
      end
    end

    defp add_route(igniter, context, router) do
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      source_str = Rewrite.Source.get(source, :content)

      if source_contains?(source_str, :demo_route) do
        igniter
      else
        Igniter.Libs.Phoenix.append_to_scope(
          igniter,
          "/",
          ~s|star_view "/stream-demo", StreamDemoPage\n|,
          with_pipelines: [:browser],
          arg2: context.web_module,
          router: router
        )
      end
    end

    # ==================================================================================
    # Notices

    defp source_contains?(source, kind) do
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(false, &find_source_node(&1, &2, kind))
      |> elem(1)
    end

    defp find_source_node(
           {:import, _meta, [{:__aliases__, _, [:StarView, :Router]} | _]} = node,
           _found?,
           :router_import
         ), do: {node, true}

    defp find_source_node({:star_view, _meta, ["/stream-demo" | _]} = node, _found?, :demo_route),
      do: {node, true}

    defp find_source_node(node, found?, _kind), do: {node, found?}

    defp add_post_setup_notice(igniter, context) do
      Igniter.add_notice(igniter, """
      StarView stream demo generated!

        * #{inspect(context.page_module)} — GET /stream-demo (SSE over POST /stream-demo)
        * #{inspect(context.ticker_module)} — broadcasts every second (added to your supervision tree)

      Start the server and open /stream-demo. Both modules are demo code —
      delete them freely (remove the ticker from application.ex too).
      """)
    end
  end
else
  defmodule Mix.Tasks.StarView.Setup.StreamPage do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"
    @moduledoc __MODULE__.Docs.long_doc()
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("Requires igniter.")
      exit({:shutdown, 1})
    end
  end
end
