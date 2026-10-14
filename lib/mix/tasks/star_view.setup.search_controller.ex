defmodule Mix.Tasks.StarView.Setup.SearchController.Docs do
  @moduledoc false

  def short_doc(), do: "Generates an example StarView demo controller with Datastar"
  def example(), do: "mix star_view.setup.search_controller"
  def long_doc(), do: "#{short_doc()}"
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.StarView.Setup.SearchController do
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
        composes: ["star_view.setup.dispatch"],
        schema: [router: :string],
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

      igniter
      |> maybe_generate_example(web_module, phoenix?)
      |> maybe_patch_router(web_module, phoenix?)
    end

    defp maybe_generate_example(igniter, web_module, false) do
      module = Module.concat([web_module, StarViewDemo])

      Igniter.Project.Module.create_module(
        igniter,
        module,
        """
        @moduledoc "Example Datastar handler using StarView with Plug."

        def handle_event(conn, "increment", signals) do
          count = Map.get(signals, "count", 0) + 1
          StarView.patch_signals(conn, %{count: count})
        end
        """
      )
    end

    defp maybe_generate_example(igniter, web_module, true) do
      controller = Module.concat([web_module, SearchController])

      template =
        Path.join(:code.priv_dir(:star_view), "templates/search_controller.ex.eex")
        |> EEx.eval_file(web_module: web_module, controller: controller)

      Igniter.Project.Module.create_module(igniter, controller, template)
    end

    defp maybe_patch_router(igniter, _web_module, false), do: igniter

    defp maybe_patch_router(igniter, web_module, true) do
      {igniter, router} = Mix.Tasks.StarView.Setup.Dispatch.select_router(igniter)
      append_example_route(igniter, web_module, router)
    end

    defp append_example_route(igniter, _web_module, nil) do
      Igniter.add_warning(igniter, "No Phoenix router found. Skipping example route setup.")
    end

    defp append_example_route(igniter, web_module, router) do
      igniter = Igniter.compose_task(igniter, "star_view.setup.dispatch")
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      source_str = Rewrite.Source.get(source, :content)

      if String.contains?(source_str, ~s("/search")) do
        igniter
      else
        Igniter.Libs.Phoenix.append_to_scope(
          igniter,
          "/",
          ~s(get "/search", SearchController, :mount),
          with_pipelines: [:browser],
          arg2: web_module,
          router: router
        )
      end
    end
  end
else
  defmodule Mix.Tasks.StarView.Setup.SearchController do
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
