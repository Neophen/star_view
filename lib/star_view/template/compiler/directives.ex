defmodule StarView.Template.Compiler.Directives do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Attributes

  def wrap(node, attrs, meta, context) do
    condition = Attributes.directive(attrs, ":if")
    generator = Attributes.directive(attrs, ":for")
    key = Attributes.directive(attrs, ":key")
    check_key!(key, generator, context)
    node = conditional(node, condition, context, meta)
    collection(node, generator, key, context, meta)
  end

  defp check_key!(nil, _generator, _context), do: :ok
  defp check_key!(_key, generator, _context) when not is_nil(generator), do: :ok

  defp check_key!({_name, _, meta}, nil, context),
    do: Compiler.error!(":key requires :for", context, meta)

  defp conditional(node, nil, _context, _meta), do: node

  defp conditional(node, condition, context, meta) do
    {condition, dependencies} = Attributes.expression(condition, context)
    meta = Map.put(meta, :dependencies, dependencies)
    shown = Compiler.node(:branch, [key: true, children: [node]], context, meta)
    hidden = Compiler.node(:branch, [key: false, children: []], context, meta)
    quote do: if(unquote(condition), do: unquote(shown), else: unquote(hidden))
  end

  defp collection(node, nil, _key, _context, _meta), do: node

  defp collection(node, generator, key, context, meta) do
    {generator, dependencies} = Attributes.expression(generator, context)
    check_generator!(generator, context, meta)
    {key_ast, _dependencies} = Attributes.expression(key, context)
    item = Compiler.node(:fragment, [key: key_ast, children: [node]], context, meta)
    entries = quote do: for(unquote(generator), do: unquote(item))
    collection_node(entries, key, context, Map.put(meta, :dependencies, dependencies))
  end

  defp check_generator!({:<-, _, [_, _]}, _context, _meta), do: :ok

  defp check_generator!(_other, context, meta),
    do: Compiler.error!(":for requires one pattern <- enumerable generator", context, meta)

  defp collection_node(entries, nil, context, meta),
    do: Compiler.node(:fragment, [children: entries], context, meta)

  defp collection_node(entries, _key, context, meta) do
    meta = Macro.escape(Compiler.metadata(context, meta))
    quote do: StarView.Template.Runtime.keyed(unquote(entries), unquote(meta))
  end
end
