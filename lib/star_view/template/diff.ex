defmodule StarView.Template.Diff do
  @moduledoc false

  # Compares two evaluated template snapshots node by node. Each comparison
  # returns one of:
  #
  #   * `:same`
  #   * `{:patches, [{selector, old_element, new_element}]}` - every change is
  #     covered by patches on existing, uniquely identified elements
  #   * `{:dirty, reason}` - the change needs an ancestor patch
  #   * `{:reset, reason}` - the snapshot pair cannot be diffed safely
  #
  # An addressable element turns a dirty subtree or its own attribute change
  # into one patch for itself and drops its descendants' patches, so batches
  # never overlap.

  alias StarView.Template
  alias StarView.Template.HTML
  alias StarView.Template.Node
  alias StarView.Template.Patch
  alias StarView.Template.Program
  alias StarView.Template.Renderer

  # Ids usable as `#id` without CSS escaping.
  @untargetable_tags ["html", "head", "body", "template"]
  # Descendants of these are not reliable `#id` targets: they are foreign
  # content, inert, raw text or not in the document tree.
  @boundary_tags ~w(head template noscript svg math script style textarea title iframe noembed noframes xmp plaintext)
  @foreign_roots ["svg", "math"]
  @foreign_namespaces [:svg, :mathml]

  @doc false
  def diff(nil, %Template{}), do: {:reset, :initial}

  def diff(%Template{fingerprint: previous}, %Template{fingerprint: next}) when previous != next,
    do: {:reset, :template_changed}

  def diff(%Template{} = previous, %Template{} = next) do
    previous = Program.template(previous)
    next = Program.template(next)
    previous |> compare_template(next) |> finish(previous, next)
  rescue
    StarView.Template.StaleProgramError -> {:reset, :template_changed}
  end

  def diff(previous, next) do
    raise ArgumentError,
          "expected nil or a StarView.Template baseline and a StarView.Template, got: " <>
            "#{inspect(previous)} and #{inspect(next)}"
  end

  defp compare_template(previous, next) do
    context = %{ids: unique_ids(previous, next), targetable?: true}
    compare_list(previous.nodes, next.nodes, context)
  end

  defp finish(:same, _previous, _next), do: {:ok, []}

  defp finish({:patches, targets}, _previous, _next),
    do: {:ok, targets |> Enum.reverse() |> Enum.map(&patch/1) |> Enum.reject(&is_nil/1)}

  defp finish(result, previous, next), do: reset(result, same_html?(previous, next))

  defp reset(_result, true), do: {:ok, []}
  defp reset({:dirty, reason}, false), do: {:reset, {:unaddressable, reason}}
  defp reset({:reset, _reason} = reset, false), do: reset

  defp same_html?(previous, next), do: Template.to_html(previous) == Template.to_html(next)

  defp patch({selector, old, new}),
    do: build_patch(selector, element_html(old), element_html(new))

  defp build_patch(_selector, html, html), do: nil
  defp build_patch(selector, _old_html, html), do: %Patch{selector: selector, elements: html}

  defp element_html(node), do: node |> Renderer.element() |> IO.iodata_to_binary()

  # Comparison

  defp compare_list(old, new, context) when length(old) == length(new) do
    old
    |> Enum.zip(new)
    |> Enum.reduce(:same, fn {left, right}, acc ->
      combine(acc, compare_node(left, right, context))
    end)
  end

  defp compare_list(_old, _new, _context), do: {:dirty, :structure_changed}

  defp compare_node(%Node{kind: kind} = old, %Node{kind: kind} = new, context),
    do: compare_kind(kind, old, new, context)

  defp compare_node(%Node{}, %Node{}, _context), do: {:dirty, :structure_changed}

  defp compare_node(old, new, _context) do
    raise ArgumentError, "invalid template nodes: #{inspect(old)} and #{inspect(new)}"
  end

  defp compare_kind(:text, %Node{value: html}, %Node{value: html}, _context), do: :same
  defp compare_kind(:text, _old, _new, _context), do: {:dirty, :text_changed}

  defp compare_kind(kind, old, new, context) when kind in [:value, :component],
    do: compare_value(old.value, new.value, context)

  defp compare_kind(:element, old, new, context), do: compare_element(old, new, context)

  defp compare_kind(:branch, %Node{key: key} = old, %Node{key: key} = new, context),
    do: compare_list(old.children, new.children, context)

  defp compare_kind(:branch, _old, _new, _context), do: {:dirty, :branch_changed}

  defp compare_kind(:fragment, %Node{key: key} = old, %Node{key: key} = new, context),
    do: compare_list(old.children, new.children, context)

  defp compare_kind(:fragment, _old, _new, _context), do: {:dirty, :key_changed}
  defp compare_kind(:keyed, old, new, context), do: compare_keyed(old, new, context)

  defp compare_kind(kind, _old, _new, _context),
    do: raise(ArgumentError, "invalid template node kind: #{inspect(kind)}")

  defp combine({:reset, _reason} = reset, _result), do: reset
  defp combine(_acc, {:reset, _reason} = reset), do: reset
  defp combine({:dirty, _reason} = dirty, _result), do: dirty
  defp combine(_acc, {:dirty, _reason} = dirty), do: dirty
  defp combine(:same, result), do: result
  defp combine(acc, :same), do: acc
  defp combine({:patches, acc}, {:patches, patches}), do: {:patches, patches ++ acc}

  # Values: own templates are walked, everything else compares rendered HTML.

  defp compare_value(old, new, context),
    do: compare_shapes(shape(old), shape(new), old, new, context)

  defp shape(%Template{}), do: :template

  defp shape(value) when is_list(value),
    do: if(Renderer.structured_list?(value), do: :templates, else: :opaque)

  defp shape(_value), do: :opaque

  defp compare_shapes(
         :template,
         :template,
         %Template{fingerprint: fingerprint} = old,
         %Template{fingerprint: fingerprint} = new,
         context
       ), do: compare_list(old.nodes, new.nodes, context)

  defp compare_shapes(:template, :template, _old, _new, _context), do: {:dirty, :template_changed}

  defp compare_shapes(:templates, :templates, old, new, context)
       when length(old) == length(new) do
    old
    |> Enum.zip(new)
    |> Enum.reduce(:same, fn {left, right}, acc ->
      combine(acc, compare_entry(left, right, context))
    end)
  end

  defp compare_shapes(:opaque, :opaque, old, new, _context),
    do: same_or_dirty(value_html(old) == value_html(new), :value_changed)

  defp compare_shapes(_old_shape, _new_shape, _old, _new, _context), do: {:dirty, :value_changed}

  defp compare_entry(old, new, context) do
    case {shape(old), shape(new)} do
      {:opaque, :opaque} -> same_or_dirty(entry_html(old) == entry_html(new), :value_changed)
      _shapes -> compare_value(old, new, context)
    end
  end

  defp value_html(value), do: value |> Renderer.value() |> IO.iodata_to_binary()
  defp entry_html(value), do: value |> Renderer.entry() |> IO.iodata_to_binary()

  defp same_or_dirty(true, _reason), do: :same
  defp same_or_dirty(false, reason), do: {:dirty, reason}

  # Elements

  defp compare_element(%Node{tag: tag} = old, %Node{tag: tag} = new, context),
    do: compare_element_shape(same_element_shape?(old, new), old, new, context)

  defp compare_element(_old, _new, _context), do: {:dirty, :element_changed}

  defp same_element_shape?(old, new) do
    Renderer.void?(old.meta) == Renderer.void?(new.meta) and namespace(old) == namespace(new)
  end

  defp compare_element_shape(false, _old, _new, _context), do: {:dirty, :element_changed}

  defp compare_element_shape(true, old, new, context) do
    children = compare_list(old.children, new.children, child_context(old, new, context))
    resolve(attributes_changed?(old, new), children, target(old, new, context), {old, new})
  end

  defp resolve(_changed?, {:reset, _reason} = reset, _selector, _pair), do: reset
  defp resolve(false, :same, _selector, _pair), do: :same
  defp resolve(false, {:patches, _targets} = patches, _selector, _pair), do: patches
  defp resolve(_changed?, {:dirty, _reason} = dirty, nil, _pair), do: dirty
  defp resolve(true, _children, nil, _pair), do: {:dirty, :attributes_changed}
  defp resolve(_changed?, _children, selector, {old, new}), do: {:patches, [{selector, old, new}]}

  defp attributes_changed?(old, new), do: attributes_html(old) != attributes_html(new)

  defp attributes_html(node), do: node |> Renderer.attributes() |> IO.iodata_to_binary()

  defp child_context(old, new, context) do
    targetable? = context.targetable? and not boundary?(old) and not boundary?(new)
    %{context | targetable?: targetable?}
  end

  defp boundary?(%Node{tag: tag, meta: meta} = node) do
    tag in @boundary_tags or String.contains?(tag, "-") or meta[:browser_owned?] == true or
      namespace(node) in @foreign_namespaces or ignore_morph?(node)
  end

  defp target(old, new, %{targetable?: true, ids: ids}) do
    id = element_id(old)

    if id != nil and id == element_id(new) and MapSet.member?(ids, id) and self_target?(old) and
         self_target?(new),
       do: "#" <> id
  end

  defp target(_old, _new, _context), do: nil

  defp self_target?(%Node{tag: tag} = node) do
    tag not in @untargetable_tags and not ignore_morph?(node) and not foreign_descendant?(node)
  end

  defp foreign_descendant?(%Node{tag: tag} = node),
    do: namespace(node) in @foreign_namespaces and tag not in @foreign_roots

  defp namespace(%Node{meta: meta}), do: meta[:namespace]

  # Datastar skips elements marked `data-ignore*`; patching them or their
  # descendants directly would bypass that ownership.
  defp ignore_morph?(%Node{attrs: attrs}), do: Enum.any?(attrs, &ignore_attribute?/1)

  defp ignore_attribute?({:static, name, _raw, _delimiter}), do: ignore_name?(name)
  defp ignore_attribute?({:dynamic, name, value}), do: ignore_names?([{name, value}])
  defp ignore_attribute?({:spread, attrs}), do: ignore_names?(attrs)

  defp ignore_names?(attrs),
    do: attrs |> HTML.flatten_spread() |> Enum.any?(fn {name, _value} -> ignore_name?(name) end)

  defp ignore_name?(name), do: name |> String.downcase() |> String.starts_with?("data-ignore")

  # Ids

  defp element_id(%Node{attrs: attrs}), do: attrs |> id_candidates() |> single_safe_id()

  # The browser keeps the first of duplicate attributes, so more than one id
  # source makes the element ambiguous.
  defp single_safe_id([id]) when is_binary(id), do: if(safe_id?(id), do: id)
  defp single_safe_id(_candidates), do: nil

  defp safe_id?(<<first, rest::binary>>) when first in ?A..?Z or first in ?a..?z,
    do: safe_id_tail?(rest)

  defp safe_id?(_id), do: false
  defp safe_id_tail?(<<>>), do: true

  defp safe_id_tail?(<<character, rest::binary>>)
       when character in ?A..?Z or character in ?a..?z or character in ?0..?9 or
              character in ~c"_-", do: safe_id_tail?(rest)

  defp safe_id_tail?(_id), do: false

  defp id_candidates(attrs), do: Enum.flat_map(attrs, &attribute_ids/1)

  defp attribute_ids({:static, name, nil, _delimiter}), do: named_ids(name, :bare)
  defp attribute_ids({:static, name, raw, _delimiter}), do: named_ids(name, raw)
  defp attribute_ids({:dynamic, name, value}), do: named_ids(name, value)

  defp attribute_ids({:spread, attrs}),
    do:
      attrs
      |> HTML.flatten_spread()
      |> Enum.flat_map(fn {name, value} -> named_ids(name, value) end)

  defp named_ids(name, value), do: if(id_name?(name), do: value_ids(value), else: [])

  defp value_ids(value) when value in [nil, false], do: []
  defp value_ids(value) when is_binary(value), do: [value]
  defp value_ids(_value), do: [:unsupported]

  defp id_name?(name), do: String.downcase(name) == "id"

  # Only ids seen exactly once in both snapshots are addressable. Ids inside
  # trusted opaque HTML are invisible here; see StarView.Template docs.
  defp unique_ids(previous, next) do
    old = previous.nodes |> tree_ids() |> Enum.frequencies()
    new = next.nodes |> tree_ids() |> Enum.frequencies()
    for {id, 1} <- old, Map.get(new, id) == 1, into: MapSet.new(), do: id
  end

  defp tree_ids(nodes), do: Enum.flat_map(nodes, &node_ids/1)

  defp node_ids(%Node{kind: :element, attrs: attrs, children: children}),
    do: Enum.filter(id_candidates(attrs), &is_binary/1) ++ tree_ids(children)

  defp node_ids(%Node{kind: kind, value: value}) when kind in [:value, :component],
    do: nested_ids(shape(value), value)

  defp node_ids(%Node{children: children}), do: tree_ids(children)

  defp nested_ids(:template, %Template{nodes: nodes}), do: tree_ids(nodes)
  defp nested_ids(:templates, list), do: Enum.flat_map(list, &nested_ids(shape(&1), &1))
  defp nested_ids(:opaque, _value), do: []

  # Keyed collections

  defp compare_keyed(old, new, context) do
    with {:ok, old_keys} <- item_keys(old.children),
         {:ok, new_keys} <- item_keys(new.children) do
      compare_items(old_keys == new_keys, old, new, context)
    end
  end

  defp compare_items(true, old, new, context),
    do: compare_list(old.children, new.children, context)

  defp compare_items(false, _old, _new, _context), do: {:dirty, :keys_changed}

  defp item_keys(items), do: items |> Enum.map(&item_key!/1) |> check_keys()

  defp item_key!(%Node{kind: :fragment, key: key}), do: key

  defp item_key!(other),
    do: raise(ArgumentError, "keyed children must be :fragment nodes, got: #{inspect(other)}")

  defp check_keys(keys), do: check_keys(keys, nil in keys)
  defp check_keys(_keys, true), do: {:reset, :missing_key}

  defp check_keys(keys, false) do
    case duplicate_key(keys, MapSet.new()) do
      nil -> {:ok, keys}
      {:duplicate, key} -> {:reset, {:duplicate_key, key}}
    end
  end

  defp duplicate_key([], _seen), do: nil

  defp duplicate_key([key | rest], seen) do
    if MapSet.member?(seen, key),
      do: {:duplicate, key},
      else: duplicate_key(rest, MapSet.put(seen, key))
  end
end
