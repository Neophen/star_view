defmodule StarView.Template.Compiler.Attributes do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Expressions
  alias StarView.Template.HTML

  @directives ~w(:if :for :key :let)

  def html(attrs, context), do: Enum.map(ordinary(attrs), &html_attribute(&1, context))

  def ordinary(attrs), do: Enum.reject(attrs, &directive?/1)

  def directive(attrs, name), do: Enum.find(attrs, &match?({^name, _, _}, &1))

  def expression({_, {:expr, value, meta}, _}, context),
    do: Expressions.parse(value, context, meta)

  def expression(nil, _context), do: {nil, []}

  def expression({name, _, meta}, context),
    do: Compiler.error!("#{name} must be an expression in braces", context, meta)

  def validate!(attrs, context, allowed \\ @directives),
    do: Enum.each(attrs, &validate_attribute!(&1, context, allowed))

  def component(attrs, context) do
    entries = Enum.map(ordinary(attrs), &component_attribute(&1, context))

    component_entries(entries, Enum.any?(entries, &match?({:spread, _}, &1)))
  end

  defp component_entries(entries, true),
    do: quote(do: StarView.Template.Runtime.component_assigns(unquote(entries)))

  defp component_entries(entries, false) do
    {bindings, fields} = Enum.map_reduce(entries, [], &component_binding/2)
    fields = fields |> Enum.uniq_by(&elem(&1, 0)) |> Enum.reverse()
    {:__block__, [], bindings ++ [{:%{}, [], fields}]}
  end

  defp component_binding({name, expression}, fields) do
    variable = Macro.unique_var(:component_value, __MODULE__)
    binding = quote generated: true, do: unquote(variable) = unquote(expression)
    {binding, [{name, variable} | fields]}
  end

  defp directive?({":" <> _, _, _}), do: true

  defp directive?({name, _, _}) when name in ~w(phx-no-format phx-no-curly-interpolation),
    do: true

  defp directive?(_attribute), do: false

  defp validate_attribute!({":" <> _ = name, _, meta}, context, allowed) do
    if name not in allowed, do: Compiler.error!("unsupported directive #{name}", context, meta)
  end

  defp validate_attribute!(_attribute, _context, _allowed), do: :ok

  defp html_attribute({:root, {:expr, value, meta}, _}, context) do
    {ast, _deps} = Expressions.parse(value, context, meta)
    quote do: {:spread, unquote(ast)}
  end

  defp html_attribute({name, value, meta}, context) do
    Compiler.validate!(name, &HTML.attribute_name!/1, context, meta)
    named_html_attribute(name, value, context)
  end

  defp named_html_attribute(name, nil, _context), do: Macro.escape({:static, name, nil, "\""})

  defp named_html_attribute(name, {:string, value, meta}, _context),
    do: Macro.escape({:static, name, value, <<meta.delimiter>>})

  defp named_html_attribute(name, {:expr, value, meta}, context) do
    {ast, _deps} = Expressions.parse(value, context, meta)
    quote do: {:dynamic, unquote(name), unquote(ast)}
  end

  # Attribute names come from trusted template source, never submitted data.
  defp component_attribute({name, nil, _}, _context),
    do: Macro.escape({String.to_atom(name), true})

  defp component_attribute({name, {:string, value, _}, _}, _context),
    do: Macro.escape({String.to_atom(name), value})

  defp component_attribute({:root, {:expr, value, meta}, _}, context) do
    {ast, _deps} = Expressions.parse(value, context, meta)
    quote do: {:spread, unquote(ast)}
  end

  defp component_attribute({name, {:expr, value, meta}, _}, context) do
    {ast, _deps} = Expressions.parse(value, context, meta)
    quote do: {unquote(String.to_atom(name)), unquote(ast)}
  end
end
