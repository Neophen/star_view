defmodule StarView.Template.Compiler.Clauses do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Expressions

  def compile(_source, clauses, meta, context) when length(clauses) < 2,
    do: Compiler.error!("case/cond requires at least one clause", context, meta)

  def compile(source, [{leading, _label, _meta} | _] = clauses, meta, context) do
    require_whitespace!(leading, context, meta)
    {ast, dependencies} = Expressions.parse(source <> "\ntrue -> nil\nend", context, meta)
    require_empty_opener!(ast, context, meta)
    context = Map.put(context, :branch_dependencies, dependencies)

    branches =
      clauses
      |> Enum.zip(tl(clauses))
      |> Enum.with_index()
      |> Enum.map(&branch(&1, context, meta))

    expression(ast, branches)
  end

  defp expression({:case, meta, [value, _options]}, branches),
    do: {:case, meta, [value, [do: branches]]}

  defp expression({:cond, meta, [_options]}, branches), do: {:cond, meta, [[do: branches]]}

  defp require_empty_opener!(
         {:case, _, [_value, [do: [{:->, _, [[true], nil]}]]]},
         _context,
         _meta
       ), do: :ok

  defp require_empty_opener!({:cond, _, [[do: [{:->, _, [[true], nil]}]]]}, _context, _meta),
    do: :ok

  defp require_empty_opener!(_ast, context, meta),
    do:
      Compiler.error!(
        "put case/cond clauses in separate EEx tags after the opening tag",
        context,
        meta
      )

  defp branch(
         {{{_leading, pattern, pattern_meta}, {children, _next, _next_meta}}, index},
         context,
         meta
       ) do
    {clause, dependencies} =
      Expressions.parse("fn " <> pattern <> "\nnil\nend", context, pattern_meta)

    {:fn, _fn_meta, [{:->, arrow_meta, [patterns, nil]}]} = clause
    require_single_pattern!(patterns, context, pattern_meta)
    dependencies = Enum.sort(Enum.uniq(context.branch_dependencies ++ dependencies))
    meta = Map.put(meta, :dependencies, dependencies)
    context = %{context | path: context.path ++ [index]}

    node =
      Compiler.node(
        :branch,
        [key: index, children: Compiler.nodes(children, context)],
        context,
        meta
      )

    {:->, arrow_meta, [patterns, node]}
  end

  defp require_whitespace!(nodes, context, meta) do
    if !Enum.all?(nodes, &whitespace?/1),
      do: Compiler.error!("case/cond cannot emit content before the first clause", context, meta)
  end

  defp whitespace?({:text, value, _meta}), do: String.trim(value) == ""
  defp whitespace?({:eex_comment, _comment}), do: true
  defp whitespace?({:eex_comment, _comment, _meta}), do: true
  defp whitespace?(_node), do: false

  defp require_single_pattern!([_pattern], _context, _meta), do: :ok

  defp require_single_pattern!(_patterns, context, meta),
    do: Compiler.error!("case/cond clauses require one pattern or condition", context, meta)
end
