defmodule StarView.Template.Compiler.Expressions do
  @moduledoc false

  def parse(source, context, meta) do
    ast =
      Code.string_to_quoted!(source,
        file: context.file,
        line: Map.get(meta, :line, context.line),
        column: Map.get(meta, :column, 1)
      )

    rewrite(ast, context)
  end

  def rewrite(ast, context) do
    ast = StarView.Events.References.track(ast, context.caller)
    {ast, dependencies} = Macro.prewalk(ast, MapSet.new(), &guard_assigns/2)
    {ast, dependencies} = Macro.postwalk(ast, dependencies, &assign(&1, &2, context))
    {ast, dependencies |> MapSet.to_list() |> Enum.sort()}
  end

  defp guard_assigns({:when, meta, arguments}, dependencies) do
    {patterns, [guard]} = Enum.split(arguments, -1)
    {guard, dependencies} = Macro.prewalk(guard, dependencies, &guard_assign/2)
    {{:when, meta, patterns ++ [guard]}, dependencies}
  end

  defp guard_assigns(ast, dependencies), do: {ast, dependencies}

  defp guard_assign({:@, meta, [{name, _, _}]}, dependencies) do
    assigns = Macro.var(:assigns, nil)

    {{{:., meta, [assigns, name]}, Keyword.put(meta, :no_parens, true), []},
     MapSet.put(dependencies, name)}
  end

  defp guard_assign(ast, dependencies), do: {ast, dependencies}

  defp assign({:render_slot, meta, args}, dependencies, _context) when length(args) in [1, 2],
    do: {slot_call(args, meta), dependencies}

  defp assign({:sigil_H, meta, _args}, _dependencies, context),
    do:
      StarView.Template.Compiler.error!(
        "legacy HEEx (~H) is incompatible; use ~STAR for nested templates",
        context,
        Map.new(meta)
      )

  defp assign({{:., _, [module, :render_slot]}, meta, args} = ast, dependencies, context)
       when length(args) in [1, 2] do
    if Macro.expand(module, context.caller) == Phoenix.Component,
      do: {slot_call(args, meta), dependencies},
      else: {ast, dependencies}
  end

  defp assign({:@, meta, [{name, _, _}]}, dependencies, _context) when is_atom(name) do
    assigns = Macro.var(:assigns, nil)

    ast =
      quote line: meta[:line] || 1 do
        StarView.Template.Runtime.fetch_assign!(unquote(assigns), unquote(name))
      end

    {ast, MapSet.put(dependencies, name)}
  end

  defp assign({:assigns, _meta, scope} = ast, dependencies, _context) when is_atom(scope),
    do: {ast, MapSet.put(dependencies, :assigns)}

  defp assign(ast, dependencies, _context), do: {ast, dependencies}

  defp slot_call(args, meta),
    do: {{:., meta, [StarView.Template.Runtime, :render_slot]}, meta, args}
end
