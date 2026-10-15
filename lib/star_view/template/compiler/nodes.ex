defmodule StarView.Template.Compiler.Nodes do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Blocks
  alias StarView.Template.Compiler.Components
  alias StarView.Template.Compiler.Elements
  alias StarView.Template.Compiler.Expressions

  def compile({:text, value, meta}, context),
    do: Compiler.node(:text, [value: value], context, meta)

  def compile({:body_expr, source, meta}, context), do: value(source, meta, context)

  def compile({:eex, source, %{opt: ~c"="} = meta}, context), do: value(source, meta, context)

  def compile({:eex_comment, _, meta}, context),
    do: Compiler.node(:text, [value: ""], context, meta)

  def compile({:eex_comment, _}, context), do: Compiler.node(:text, [value: ""], context)

  def compile({:eex, _source, meta}, context),
    do:
      Compiler.error!(
        "non-output EEx code is not supported; compute assigns before rendering",
        context,
        meta
      )

  def compile({:eex_block, source, clauses, meta}, context),
    do: Blocks.compile(source, clauses, meta, context)

  def compile({:block, :tag, name, attrs, children, meta, _close}, context),
    do: Elements.compile(name, attrs, children, meta, context)

  def compile({:self_close, :tag, name, attrs, meta}, context),
    do: Elements.compile(name, attrs, [], meta, context)

  def compile({:block, type, name, attrs, children, meta, _close}, context)
      when type in [:local_component, :remote_component],
      do: Components.compile(type, name, attrs, children, meta, context)

  def compile({:self_close, type, name, attrs, meta}, context)
      when type in [:local_component, :remote_component],
      do: Components.compile(type, name, attrs, [], meta, context)

  def compile(node, context),
    do: Compiler.error!("unsupported template construct #{inspect(elem(node, 0))}", context)

  defp value(source, meta, context) do
    {ast, dependencies} = Expressions.parse(source, context, meta)
    Compiler.node(:value, [value: ast], context, Map.put(meta, :dependencies, dependencies))
  end
end
