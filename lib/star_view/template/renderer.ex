defmodule StarView.Template.Renderer do
  @moduledoc false

  import Kernel, except: [node: 1]

  alias StarView.Template
  alias StarView.Template.HTML
  alias StarView.Template.Node
  alias StarView.Template.Runtime

  @tag_name ~r/\A[A-Za-z][A-Za-z0-9_.:-]*\z/
  @container_kinds [:branch, :keyed, :fragment]

  @doc false
  def to_iodata(%Template{nodes: nodes}), do: nodes(nodes)

  @doc false
  def nodes(nodes) when is_list(nodes), do: Enum.map(nodes, &node/1)

  def nodes(other),
    do: raise(ArgumentError, "expected a list of template nodes, got: #{inspect(other)}")

  @doc false
  def node(%Node{kind: :text, value: html}) when is_binary(html), do: html
  def node(%Node{kind: :value, value: value}), do: value(value)

  def node(%Node{kind: :component, value: value}),
    do: value |> Runtime.native_template!("component") |> to_iodata()

  def node(%Node{kind: :element} = node), do: element(node)

  def node(%Node{kind: kind, children: children}) when kind in @container_kinds,
    do: nodes(children)

  def node(other), do: raise(ArgumentError, "invalid template node: #{inspect(other)}")

  @doc false
  def value(%Template{} = template), do: to_iodata(template)
  def value(list) when is_list(list), do: list_value(list, structured_list?(list))
  def value(value), do: HTML.escape(value)

  @doc false
  def structured_list?([%_{} | _tail]), do: true

  def structured_list?([head | tail]) when is_list(head),
    do: structured_list?(head) or structured_list?(tail)

  def structured_list?([_head | tail]), do: structured_list?(tail)
  def structured_list?(_tail), do: false

  @doc false
  def attributes(%Node{attrs: attrs}), do: HTML.attributes(attrs)

  @doc false
  def element(%Node{tag: tag, children: children, meta: meta} = node) do
    tag = tag!(tag)
    open = [?<, tag, attributes(node), ?>]
    close(open, tag, children, void?(meta))
  end

  @doc false
  def void?(meta), do: meta[:void?] == true

  # Values may hold native templates and ordinary safe data. Keep iodata
  # integers as characters when rendering their surrounding list.
  defp list_value(list, true), do: Enum.map(list, &entry/1)
  defp list_value(list, false), do: HTML.escape(list)

  @doc false
  def entry(character) when is_integer(character), do: HTML.escape([character])
  def entry(value), do: value(value)

  defp close(open, _tag, [], true), do: open

  defp close(_open, tag, _children, true),
    do: raise(ArgumentError, "void element <#{tag}> cannot have children")

  defp close(open, tag, children, false), do: [open, nodes(children), "</", tag, ?>]

  @doc false
  def tag!(tag) when is_binary(tag) do
    if !Regex.match?(@tag_name, tag),
      do: raise(ArgumentError, "invalid tag name: #{inspect(tag)}")

    tag
  end

  def tag!(tag), do: raise(ArgumentError, "invalid tag name: #{inspect(tag)}")
end
