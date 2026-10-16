defmodule StarView.Template.Runtime do
  @moduledoc false

  alias StarView.Template
  alias StarView.Template.Node
  alias StarView.Template.Program

  @legacy_types [
    Phoenix.LiveView.Rendered,
    Phoenix.LiveView.Comprehension,
    Phoenix.LiveView.Component
  ]

  def fetch_assign!(assigns, name) do
    case Map.fetch(assigns, name) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "missing @#{name} assign in ~STAR template"
    end
  end

  def component(fun, assigns, meta) do
    result = fun.(Map.put_new(assigns, :__changed__, nil)) |> component_result!(fun)

    %Node{kind: :component, value: result, meta: meta}
  end

  defp component_result!(%Template{} = template, _fun), do: template
  defp component_result!(other, fun), do: native_template!(other, "component #{inspect(fun)}")

  def native_template!(%Template{} = template, _origin), do: template

  def native_template!(_value, origin) do
    raise ArgumentError,
          "~STAR #{origin} must return StarView.Template; legacy HEEx (~H) values are incompatible. Convert the component and its slots to ~STAR."
  end

  def reject_legacy!(%{__struct__: type}) when type in @legacy_types,
    do: native_template!(nil, "value")

  def reject_legacy!([head | tail] = values) do
    reject_legacy!(head)
    reject_legacy!(tail)
    values
  end

  def reject_legacy!(value), do: value

  def component_assigns(entries) do
    Enum.reduce(entries, %{}, &put_component_attribute/2)
  end

  def slots(entries), do: Enum.reduce(entries, %{}, &put_slot/2)

  defp put_slot({name, nil}, slots), do: Map.put_new(slots, name, [])
  defp put_slot({name, value}, slots), do: Map.update(slots, name, [value], &(&1 ++ [value]))

  def render_slot(entries, argument \\ nil)
  def render_slot([], _argument), do: nil
  def render_slot([entry], argument), do: render_slot(entry, argument)

  def render_slot(entries, argument) when is_list(entries),
    do: Enum.map(entries, &render_slot(&1, argument))

  def render_slot(%{inner_block: block}, argument) when is_function(block, 2),
    do: block.(nil, argument) |> native_template!("slot")

  def render_slot(%{inner_block: _legacy}, _argument), do: native_template!(nil, "slot")

  def render_slot(_entry, _argument),
    do: raise(ArgumentError, "cannot render a slot without inner content")

  defp put_component_attribute({:spread, attrs}, assigns), do: Map.merge(assigns, Map.new(attrs))

  defp put_component_attribute({name, value}, assigns) when is_atom(name),
    do: Map.put(assigns, name, value)

  def keyed(children, meta) do
    keys = Enum.map(children, &child_key/1)
    ensure_present_keys!(keys)
    ensure_unique_keys!(keys)
    %Node{kind: :keyed, children: children, meta: meta}
  end

  defp child_key(%Program{} = program), do: Program.node_key(program)
  defp child_key(child), do: child.key

  defp ensure_present_keys!(keys) do
    if nil in keys, do: raise(ArgumentError, "~STAR :key values must not be nil")
  end

  defp ensure_unique_keys!(keys) do
    if length(keys) != MapSet.size(MapSet.new(keys)),
      do: raise(ArgumentError, "~STAR :key values must be unique within a collection")
  end
end
