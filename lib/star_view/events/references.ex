defmodule StarView.Events.References do
  @moduledoc false

  alias StarView.Events

  @verbs ~w(get post put patch delete)a

  def track(ast, %{module: nil}), do: ast
  def track(ast, env), do: track_kind(ast, event_kind(env.module), env)

  defp event_kind(module) do
    if Module.open?(module), do: Module.get_attribute(module, :star_view_event_kind)
  end

  defp track_kind(ast, nil, _env), do: ast
  defp track_kind(ast, kind, env), do: Macro.prewalk(ast, &track_call(&1, kind, env))

  defp track_call({verb, meta, args} = ast, :controller, env)
       when verb in @verbs and length(args) in [1, 2] do
    record!(hd(args), verb, meta, env)
    ast
  end

  defp track_call({:event, meta, args} = ast, :component, env) when length(args) in [1, 2] do
    record!(hd(args), event_verb!(args, meta, env), meta, env)
    ast
  end

  defp track_call({:event, meta, args} = ast, :page, env) when length(args) in [1, 2] do
    if {:function, StarView.Page.Helpers} in Macro.Env.lookup_import(env, {:event, length(args)}),
      do: record!(hd(args), event_verb!(args, meta, env), meta, env)

    ast
  end

  defp track_call(ast, _kind, _env), do: ast

  defp record!(name, verb, meta, env) when is_binary(name) do
    reference = %{
      name: name,
      method: verb |> Atom.to_string() |> String.upcase(),
      file: env.file,
      line: meta[:line] || env.line
    }

    Module.put_attribute(env.module, :star_view_event_refs, reference)
  end

  defp record!(_name, _verb, meta, env),
    do:
      error!(
        "checked ~STAR event names must be literal strings; put varying values in signals",
        env.file,
        meta[:line] || env.line
      )

  defp event_verb!([_name], _meta, _env), do: :post

  defp event_verb!([_name, opts], meta, env) do
    if not is_list(opts) or not Keyword.keyword?(opts),
      do:
        error!(
          "checked event/2 needs literal options so its HTTP verb can be checked",
          env.file,
          meta[:line] || env.line
        )

    literal_verb!(Keyword.get(opts, :verb, :post), meta, env)
  end

  defp literal_verb!(verb, _meta, _env) when verb in @verbs, do: verb

  defp literal_verb!(_verb, meta, env),
    do:
      error!(
        "checked event/2 needs a literal get, post, put, patch or delete verb",
        env.file,
        meta[:line] || env.line
      )

  def validate!(references, registry),
    do: Enum.each(references, &validate_reference!(&1, registry))

  defp validate_reference!(reference, registry) do
    case Events.check_registry(registry, reference.name, reference.method) do
      :ok ->
        :ok

      {:error, :unknown_event} ->
        error!(
          "unknown checked event #{inspect(reference.name)}; define a matching handle_event/3 clause",
          reference.file,
          reference.line
        )

      {:error, {:method, methods}} ->
        error!(
          "checked event #{inspect(reference.name)} handles #{Enum.join(methods, ", ")}, not #{reference.method}",
          reference.file,
          reference.line
        )
    end
  end

  defp error!(message, file, line),
    do: raise(CompileError, file: file, line: line, description: message)
end
