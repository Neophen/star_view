defmodule StarView.Events.Definitions do
  @moduledoc false

  @methods ~w(GET POST PUT PATCH DELETE)

  def registry!(env) do
    if Module.defines?(env.module, {:__star_view_events__, 0}),
      do: error!("__star_view_events__/0 is reserved for the generated event contract", env, [])

    env.module
    |> Module.get_definition({:handle_event, 3})
    |> clauses!(env)
    |> Enum.reduce(%{}, &register(&1, &2, env))
    |> Map.new(&sort_methods/1)
  end

  defp clauses!({:v1, :def, _meta, clauses}, _env), do: clauses

  defp clauses!(nil, _env), do: []

  defp clauses!(_definition, env),
    do: error!("checked events require public handle_event/3 clauses", env, [])

  defp register({meta, [name, _signals, conn], _guards, _body}, registry, env)
       when is_binary(name) do
    validate_name!(name, env, meta)
    method = conn |> method() |> method!(name, env, meta)
    Map.update(registry, name, [method], &[method | &1])
  end

  defp register({_meta, [{name, _meta2, scope}, _signals, _conn], _guards, _body}, registry, _env)
       when is_atom(name) and is_atom(scope), do: registry

  defp register({meta, _args, _guards, _body}, _registry, env),
    do:
      error!(
        "checked events need literal event names; put record IDs in signals instead of event-name patterns",
        env,
        meta
      )

  defp method({:=, _, [left, right]}), do: method(left) || method(right)
  defp method({:%, _, [Plug.Conn, map]}), do: method(map)
  defp method({:%{}, _, entries}), do: Keyword.get(entries, :method)
  defp method(_pattern), do: nil

  defp method!(method, _name, _env, _meta) when method in @methods, do: method

  defp method!(_method, name, env, meta),
    do:
      error!(
        "event #{inspect(name)} needs a literal method pattern, e.g. %{method: \"POST\"} = conn (GET, POST, PUT, PATCH or DELETE)",
        env,
        meta
      )

  defp validate_name!(name, env, meta) do
    StarView.Actions.encode_segment!(name)
  rescue
    _error in ArgumentError ->
      error!("checked event names must be valid, nonempty URL segments", env, meta)
  end

  defp sort_methods({name, methods}), do: {name, methods |> Enum.uniq() |> Enum.sort()}

  defp error!(message, env, meta),
    do: raise(CompileError, file: env.file, line: meta[:line] || env.line, description: message)
end
