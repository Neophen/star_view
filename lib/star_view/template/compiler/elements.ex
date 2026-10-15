defmodule StarView.Template.Compiler.Elements do
  @moduledoc false

  alias StarView.Template.Compiler
  alias StarView.Template.Compiler.Attributes
  alias StarView.Template.Compiler.Directives
  alias StarView.Template.Renderer

  @void ~w(area base br col embed hr img input link meta param source track wbr)

  def compile(name, attrs, children, meta, context) do
    Compiler.validate!(name, &Renderer.tag!/1, context, meta)
    Attributes.validate!(attrs, context, ~w(:if :for :key))
    element_context = %{context | namespace: namespace(name, context.namespace)}
    children_context = child_context(name, element_context)
    meta = Map.put(meta, :void?, name in @void or meta[:closing] == :void)

    fields = [
      tag: name,
      attrs: Attributes.html(attrs, context),
      children: Compiler.nodes(children, children_context)
    ]

    node = Compiler.node(:element, fields, element_context, meta)
    Directives.wrap(node, attrs, meta, context)
  end

  defp namespace("svg", _parent), do: :svg
  defp namespace("math", _parent), do: :mathml
  defp namespace(_name, parent), do: parent

  defp child_context("foreignObject", %{namespace: :svg} = context),
    do: %{context | namespace: :html}

  defp child_context(_name, context), do: context
end
