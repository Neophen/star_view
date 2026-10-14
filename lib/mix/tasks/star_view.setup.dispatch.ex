if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.StarView.Setup.Dispatch do
    @shortdoc "Adds Phoenix dispatch routing and Datastar CSRF compatibility"
    @moduledoc """
    Adds a POST `/ds/:module/:event` route for `StarView.Dispatch` and inserts
    `StarView.Plug.RenameCsrfParam` before browser CSRF protection.

    This task does not generate sample controllers. Register additional HTTP
    verbs explicitly when your application uses their action helpers.
    """
    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :star_view,
        example: "mix star_view.setup.dispatch",
        composes: [],
        schema: [],
        defaults: []
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      {igniter, router} = select_router(igniter)
      configure_router(igniter, router)
    end

    @doc false
    def select_router(igniter) do
      case Map.fetch(igniter.assigns, :star_view_router) do
        {:ok, router} -> {igniter, router}
        :error -> discover_router(igniter)
      end
    end

    defp discover_router(igniter) do
      {igniter, router} =
        Igniter.Libs.Phoenix.select_router(
          igniter,
          "Which Phoenix router should StarView add routes to?"
        )

      {Igniter.assign(igniter, :star_view_router, router), router}
    end

    defp configure_router(igniter, nil) do
      Igniter.add_warning(igniter, "No Phoenix router found. Skipping dispatch setup.")
    end

    defp configure_router(igniter, router) do
      igniter
      |> ensure_dispatch_route(router)
      |> ensure_csrf_rename_plug(router)
    end

    defp ensure_dispatch_route(igniter, router) do
      if post_dispatch_route?(router_source(igniter, router)) do
        igniter
      else
        append_dispatch_route(igniter, router)
      end
    end

    defp post_dispatch_route?(source) do
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(false, &find_post_dispatch_route/2)
      |> elem(1)
    end

    defp find_post_dispatch_route({:post, _meta, ["/ds/:module/:event" | _args]} = node, _found?),
      do: {node, true}

    defp find_post_dispatch_route(node, found?), do: {node, found?}

    defp append_dispatch_route(igniter, router) do
      Igniter.Libs.Phoenix.append_to_scope(
        igniter,
        "/",
        ~s(post "/ds/:module/:event", StarView.Dispatch, [], alias: false),
        with_pipelines: [:browser],
        arg2: Igniter.Libs.Phoenix.web_module(igniter),
        router: router
      )
    end

    @doc false
    def ensure_csrf_rename_plug(igniter, router) do
      if String.contains?(router_source(igniter, router), "StarView.Plug.RenameCsrfParam") do
        igniter
      else
        Igniter.Project.Module.find_and_update_module!(igniter, router, &insert_csrf_rename/1)
      end
    end

    defp insert_csrf_rename(zipper) do
      with {:ok, pipeline} <-
             Igniter.Code.Function.move_to_function_call(
               zipper,
               :pipeline,
               2,
               &browser_pipeline?/1
             ),
           {:ok, pipeline_block} <- Igniter.Code.Common.move_to_do_block(pipeline),
           {:ok, protect_from_forgery} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               pipeline_block,
               :plug,
               [1, 2],
               &csrf_protection?/1
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
           "Could not add StarView.Plug.RenameCsrfParam to the browser pipeline. " <>
             "Add it before `plug :protect_from_forgery` manually."}
      end
    end

    defp browser_pipeline?(zipper),
      do: Igniter.Code.Function.argument_equals?(zipper, 0, :browser)

    defp csrf_protection?(zipper),
      do: Igniter.Code.Function.argument_equals?(zipper, 0, :protect_from_forgery)

    defp router_source(igniter, router) do
      {_, source, _zipper} = Igniter.Project.Module.find_module!(igniter, router)
      Rewrite.Source.get(source, :content)
    end
  end
else
  defmodule Mix.Tasks.StarView.Setup.Dispatch do
    @shortdoc "Adds Phoenix dispatch routing and Datastar CSRF compatibility"
    @moduledoc """
    Adds a POST `/ds/:module/:event` route for `StarView.Dispatch` and inserts
    `StarView.Plug.RenameCsrfParam` before browser CSRF protection.

    This task does not generate sample controllers. Register additional HTTP
    verbs explicitly when your application uses their action helpers.
    """
    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("Requires igniter.")
      exit({:shutdown, 1})
    end
  end
end
