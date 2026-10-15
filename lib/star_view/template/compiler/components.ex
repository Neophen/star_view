defmodule StarView.Template.Compiler.Components do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Attributes
  alias StarView.Template.Compiler.Directives
  alias StarView.Template.Compiler.Expressions

  def compile(type, name, attrs, children, meta, context) do
    Attributes.validate!(attrs, context)
    base = Attributes.component(attrs, context)
    slots = slots(children, Attributes.directive(attrs, ":let"), context)
    assigns = quote do: Map.merge(unquote(base), unquote(slots))
    function = capture(type, name, meta, context)
    location = Macro.escape(Compiler.metadata(context, meta))

    node =
      quote do:
              StarView.Template.Runtime.component(
                unquote(function),
                unquote(assigns),
                unquote(location)
              )

    Directives.wrap(node, attrs, meta, context)
  end

  defp capture(:local_component, name, meta, _context) do
    function = {String.to_atom(name), [line: meta.line], nil}
    {:&, [line: meta.line], [{:/, [], [function, 1]}]}
  end

  defp capture(:remote_component, name, meta, context) do
    function = Code.string_to_quoted!(name, file: context.file, line: meta.line)
    {:&, [line: meta.line], [{:/, [], [function, 1]}]}
  end

  defp slots(children, default_pattern, context) do
    {named, content} = Enum.split_with(children, &named_slot?/1)
    named = named |> Enum.with_index() |> Enum.map(&named_slot(&1, context))
    inner = default_slot(content, default_pattern, context)
    entries = [inner | named]
    quote do: StarView.Template.Runtime.slots(unquote(entries))
  end

  defp named_slot?({:block, :slot, _, _, _, _, _}), do: true
  defp named_slot?({:self_close, :slot, _, _, _}), do: true
  defp named_slot?(_node), do: false

  defp named_slot({{:block, :slot, name, attrs, children, meta, _}, index}, context),
    do: slot(name, attrs, children, meta, nested(context, index))

  defp named_slot({{:self_close, :slot, name, attrs, meta}, index}, context),
    do: slot(name, attrs, [], meta, nested(context, index))

  defp default_slot([], nil, _context), do: Macro.escape({:inner_block, nil})

  defp default_slot(children, pattern, context) do
    attrs = List.wrap(pattern)
    slot("inner_block", attrs, children, %{line: context.line}, context)
  end

  defp slot(name, attrs, children, _meta, context) do
    Attributes.validate!(attrs, context, [":let"])
    slot_name = String.to_atom(name)
    values = Attributes.component(attrs, context)
    content = Compiler.nodes(children, context)
    template = Compiler.template(content, context.fingerprint, context)
    block = inner_block(template, Attributes.directive(attrs, ":let"), context)

    quote do
      {unquote(slot_name),
       Map.merge(unquote(values), %{__slot__: unquote(slot_name), inner_block: unquote(block)})}
    end
  end

  defp inner_block(template, nil, _context),
    do: quote(do: fn _changed, _argument -> unquote(template) end)

  defp inner_block(template, {_name, {:expr, source, meta}, _}, context) do
    {pattern, _dependencies} = Expressions.parse(source, context, meta)
    quote do: fn _changed, unquote(pattern) -> unquote(template) end
  end

  defp inner_block(_template, {_name, _value, meta}, context),
    do: Compiler.error!(":let must be a pattern in braces", context, meta)

  defp nested(context, index), do: %{context | path: context.path ++ [:slot, index]}
end
