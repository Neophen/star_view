defmodule StarView.Template.Compiler.Programs do
  @moduledoc false

  alias StarView.Template.Compiler.Binaries
  alias StarView.Template.HTML

  # One skeleton produces both executable clauses. Only evaluated slot data is
  # public; there is no second, mutable copy of the static markup to trust.
  def compile(nodes, context \\ %{}) do
    {render, tree, state} = nodes(nodes, %{bindings: [], variables: [], context: context})
    tuple = {:{}, [], state.variables}
    key = root_key(tree)

    run =
      quote generated: true do
        fn
          :render, unquote(tuple) -> unquote(coalesce(render))
          :nodes, unquote(tuple) -> unquote(tree)
          :key, unquote(tuple) -> unquote(key)
          _mode, _values -> raise ArgumentError, "invalid compiled ~STAR values"
        end
      end

    run = register(run, context)

    quote generated: true do
      unquote_splicing(state.bindings)
      %StarView.Template.Program{run: unquote(run), values: unquote(tuple)}
    end
  end

  defmacro __before_compile__(env) do
    Module.put_attribute(env.module, :star_view_programs_emitted, true)

    definitions =
      env.module
      |> Module.get_attribute(:star_view_programs)
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.flat_map(&definitions/1)

    quote do: (unquote_splicing(definitions))
  end

  defp definitions({name, {:fn, _, clauses}}),
    do: [quote(do: @doc(false)) | Enum.map(clauses, &definition(name, &1))]

  defp definition(name, {:->, _, [[mode, values], body]}) do
    quote generated: true do
      def unquote(name)(unquote(mode), unquote(values)), do: unquote(body)
    end
  end

  defp register(run, %{module: module}) when not is_nil(module) do
    if Module.open?(module) and Module.get_attribute(module, :star_view_programs_emitted) != true,
      do: register_open_module(run, module),
      else: run
  end

  defp register(run, _context), do: run

  defp register_open_module(run, module) do
    register_hook(module)
    # Macro.to_string drops fresh variable counters, so an unchanged skeleton
    # keeps its name across recompiles. Names come only from compiler source.
    digest = :crypto.hash(:sha256, Macro.to_string(run)) |> Base.encode16(case: :lower)
    name = String.to_atom("__star_" <> digest)
    Module.put_attribute(module, :star_view_programs, {name, run})
    quote do: &(unquote(module).unquote(name) / 2)
  end

  defp register_hook(module) do
    if not Module.has_attribute?(module, :star_view_programs) do
      Module.register_attribute(module, :star_view_programs, accumulate: true)
      Module.put_attribute(module, :before_compile, __MODULE__)
    end
  end

  defp nodes(list, state) when is_list(list) do
    {entries, state} = Enum.map_reduce(list, state, &node/2)
    {Enum.flat_map(entries, &elem(&1, 0)), Enum.map(entries, &elem(&1, 1)), state}
  end

  defp nodes(expression, state) do
    {variable, state} = slot(nested(expression, state.context), state)
    {[quote(do: StarView.Template.Renderer.nodes(unquote(variable)))], variable, state}
  end

  defp node({:%, meta, [StarView.Template.Node, {:%{}, map_meta, fields}]} = ast, state) do
    if meta[:star_node] do
      {render, fields, state} = fields(Keyword.fetch!(fields, :kind), fields, state)
      {{render, {:%, meta, [StarView.Template.Node, {:%{}, map_meta, fields}]}}, state}
    else
      opaque_node(ast, state)
    end
  end

  defp node(expression, state), do: opaque_node(expression, state)

  defp opaque_node(expression, state) do
    {variable, state} = slot(nested(expression, state.context), state)
    {{[quote(do: StarView.Template.Renderer.node(unquote(variable)))], variable}, state}
  end

  defp fields(:text, fields, state), do: {[Keyword.fetch!(fields, :value)], fields, state}

  defp fields(:value, fields, state) do
    {variable, state} = slot(Keyword.fetch!(fields, :value), state)
    render = quote do: StarView.Template.Renderer.value(unquote(variable))
    {[render], Keyword.put(fields, :value, variable), state}
  end

  defp fields(:element, fields, state) do
    tag = Keyword.fetch!(fields, :tag)
    {attributes, attrs, state} = attributes(Keyword.fetch!(fields, :attrs), state)
    {children, tree, state} = nodes(Keyword.fetch!(fields, :children), state)
    {meta, []} = Code.eval_quoted(Keyword.fetch!(fields, :meta))
    closing = if meta[:void?], do: [], else: children ++ ["</" <> tag <> ">"]
    render = ["<" <> tag] ++ attributes ++ [">"] ++ closing
    fields = fields |> Keyword.put(:attrs, attrs) |> Keyword.put(:children, tree)
    {render, fields, state}
  end

  defp fields(kind, fields, state) when kind in [:branch, :fragment, :keyed] do
    {fields, state} = key(fields, state)
    {render, tree, state} = nodes(Keyword.fetch!(fields, :children), state)
    {render, Keyword.put(fields, :children, tree), state}
  end

  defp key(fields, state) do
    expression = Keyword.get(fields, :key)

    if is_atom(expression) or is_binary(expression) or is_number(expression),
      do: {fields, state},
      else: dynamic_key(fields, state)
  end

  defp dynamic_key(fields, state) do
    {variable, state} = slot(Keyword.fetch!(fields, :key), state)
    {Keyword.put(fields, :key, variable), state}
  end

  defp attributes(attrs, state) do
    {entries, state} = Enum.map_reduce(attrs, state, &attribute/2)
    {Enum.flat_map(entries, &List.wrap(elem(&1, 0))), Enum.map(entries, &elem(&1, 1)), state}
  end

  defp attribute({:{}, _, [:static, name, raw, delimiter]} = ast, state) do
    html = HTML.attribute({:static, name, raw, delimiter}) |> IO.iodata_to_binary()
    {{html, ast}, state}
  end

  defp attribute({:{}, meta, [:dynamic, "class", [head | _] = expression]}, state)
       when is_binary(head) do
    {prefix, tail} = Enum.split_while(expression, &is_binary/1)
    class_attribute(prefix, tail, meta, state)
  end

  defp attribute({:{}, meta, [:dynamic, name, expression]}, state),
    do: dynamic_attribute(name, expression, meta, state, Binaries.extract(expression))

  defp attribute({:spread, expression}, state) do
    {variable, state} = slot(expression, state)
    render = quote do: StarView.Template.HTML.attribute({:spread, unquote(variable)})
    {{render, {:spread, variable}}, state}
  end

  defp dynamic_attribute(name, expression, meta, state, :error) do
    {variable, state} = slot(expression, state)
    render = quote do: StarView.Template.HTML.compiled_attribute(unquote(name), unquote(variable))
    {{render, {:{}, meta, [:dynamic, name, variable]}}, state}
  end

  defp dynamic_attribute(name, _expression, meta, state, {:ok, parts}) do
    {entries, state} = Enum.map_reduce(parts, state, &binary_part/2)

    checks =
      entries |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_binary/1) |> Enum.map(&binary_check/1)

    state = %{state | bindings: state.bindings ++ checks}
    render = [" " <> name <> "=\""] ++ Enum.map(entries, &elem(&1, 0)) ++ ["\""]
    value = {:<<>>, [], Enum.map(entries, &binary_segment(elem(&1, 1)))}
    {{render, {:{}, meta, [:dynamic, name, value]}}, state}
  end

  defp binary_part(binary, state) when is_binary(binary),
    do: {{HTML.escape(binary) |> IO.iodata_to_binary(), binary}, state}

  defp binary_part({:dynamic, expression}, state) do
    {variable, state} = slot(expression, state)
    render = quote do: StarView.Template.HTML.escape_binary_part(unquote(variable))
    {{render, variable}, state}
  end

  defp binary_check(expression),
    do: quote(do: StarView.Template.HTML.binary_part!(unquote(expression)))

  defp binary_segment(binary) when is_binary(binary), do: binary
  defp binary_segment(expression), do: {:"::", [], [expression, {:binary, [], nil}]}

  defp class_attribute(prefix, [], meta, state) do
    html = HTML.compiled_attribute("class", prefix) |> IO.iodata_to_binary()
    {{html, {:{}, meta, [:dynamic, "class", prefix]}}, state}
  end

  defp class_attribute(prefix, tail, meta, state) do
    {variable, state} = slot(tail, state)
    escaped = prefix |> Enum.join(" ") |> HTML.escape() |> IO.iodata_to_binary()
    render = quote do: StarView.Template.HTML.compiled_class(unquote(escaped), unquote(variable))

    value =
      quote do: StarView.Template.HTML.compiled_class_value(unquote(prefix), unquote(variable))

    {{render, {:{}, meta, [:dynamic, "class", value]}}, state}
  end

  defp slot(expression, state) do
    {name, meta, context} =
      Macro.unique_var(String.to_atom("star_value_#{length(state.variables)}"), __MODULE__)

    variable = {name, Keyword.put(meta, :generated, true), context}
    binding = quote generated: true, do: unquote(variable) = unquote(expression)

    {variable,
     %{state | bindings: state.bindings ++ [binding], variables: state.variables ++ [variable]}}
  end

  # Only compiler-marked node expressions are lowered. User expressions and
  # already-generated programs keep their normal evaluation semantics.
  defp nested({:%, meta, [StarView.Template.Node, _]} = ast, context) do
    if meta[:star_node], do: compile([ast], context), else: ast
  end

  defp nested({:%, _, [StarView.Template.Program, _]} = ast, _context), do: ast
  defp nested({:fn, _, _} = ast, _context), do: ast
  defp nested(list, context) when is_list(list), do: Enum.map(list, &nested(&1, context))

  defp nested(tuple, context) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&nested(&1, context)) |> List.to_tuple()

  defp nested(other, _context), do: other

  defp root_key([{:%, _, [StarView.Template.Node, {:%{}, _, fields}]}]),
    do: Keyword.get(fields, :key)

  defp root_key(_tree), do: nil

  defp coalesce(parts) do
    parts |> Enum.reduce([], &merge/2) |> Enum.reverse()
  end

  defp merge(binary, [previous | tail]) when is_binary(binary) and is_binary(previous),
    do: [previous <> binary | tail]

  defp merge(part, acc), do: [part | acc]
end
