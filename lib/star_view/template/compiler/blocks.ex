defmodule StarView.Template.Compiler.Blocks do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Clauses
  alias StarView.Template.Compiler.Expressions

  def compile(source, clauses, meta, context) do
    form = Regex.run(~r/\A\s*(if|unless|for|case|cond)\b/, source, capture: :all_but_first)
    compile_form(form, source, clauses, meta, context)
  end

  defp compile_form([form], source, clauses, meta, context) when form in ["case", "cond"],
    do: Clauses.compile(source, clauses, meta, context)

  defp compile_form([_form], source, clauses, meta, context) do
    {ast, dependencies} = Expressions.parse(source <> "\nnil\nend", context, meta)
    block(ast, clauses, Map.put(meta, :dependencies, dependencies), context)
  end

  defp compile_form(nil, _source, _clauses, meta, context),
    do:
      Compiler.error!(
        "unsupported EEx block; move this control flow into a helper",
        context,
        meta
      )

  defp block({name, _, [condition, _]}, clauses, meta, context) when name in [:if, :unless] do
    {positive, negative} = branches(clauses, context, meta)
    positive = Compiler.node(:branch, [key: true, children: positive], context, meta)
    negative = Compiler.node(:branch, [key: false, children: negative], context, meta)
    {name, [line: meta.line], [condition, [do: positive, else: negative]]}
  end

  defp block({:for, expression_meta, args}, [{children, "end", _}], meta, context) do
    qualifiers = Enum.drop(args, -1)
    require_plain_for!(List.last(args), context, meta)
    item = Compiler.node(:fragment, [children: Compiler.nodes(children, context)], context, meta)
    entries = {:for, expression_meta, qualifiers ++ [[do: item]]}
    Compiler.node(:fragment, [children: entries], context, meta)
  end

  defp block(_other, _clauses, meta, context),
    do:
      Compiler.error!(
        "this proof supports if, unless and plain for blocks; move other control flow into helpers",
        context,
        meta
      )

  defp branches([{children, "end", _}], context, _meta),
    do: {Compiler.nodes(children, context), []}

  defp branches([{yes, "else", _}, {no, "end", _}], context, _meta),
    do: {Compiler.nodes(yes, nested(context, 0)), Compiler.nodes(no, nested(context, 1))}

  defp branches(_clauses, context, meta),
    do: Compiler.error!("unsupported conditional branch form", context, meta)

  defp nested(context, index), do: %{context | path: context.path ++ [index]}

  defp require_plain_for!([do: nil], _context, _meta), do: :ok

  defp require_plain_for!(_options, context, meta),
    do: Compiler.error!("for options such as into/reduce are not supported", context, meta)
end
