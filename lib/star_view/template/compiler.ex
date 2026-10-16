defmodule StarView.Template.Compiler do
  @moduledoc false

  alias StarView.Template.Compiler.Nodes
  alias StarView.Template.Compiler.Programs
  alias StarView.Template.PhoenixParser

  def compile(source, caller, meta) do
    require_assigns!(caller)
    nodes = PhoenixParser.parse!(source, caller, meta)
    fingerprint = fingerprint(source, caller)
    context = Map.put(context(caller), :fingerprint, fingerprint)
    compiled = nodes(nodes, context)
    PhoenixParser.validate!(source, caller, meta)
    template = template(compiled, fingerprint, context)

    quote do
      _ = unquote(Macro.var(:assigns, nil))
      unquote(template)
    end
  end

  def nodes(nodes, context) do
    nodes |> Enum.with_index() |> Enum.map(&compile_node(&1, context))
  end

  defp compile_node({node, index}, context),
    do: Nodes.compile(node, %{context | path: context.path ++ [index]})

  def template(nodes, fingerprint, context) do
    program = Programs.compile(nodes, context)

    quote do
      %StarView.Template{
        fingerprint: unquote(fingerprint),
        nodes: nil,
        program: unquote(program),
        source: unquote(Macro.escape(Map.take(context, [:file, :line, :module, :function])))
      }
    end
  end

  def node(kind, fields, context, meta \\ %{}) do
    entries = [kind: kind, meta: Macro.escape(metadata(context, meta))] ++ fields

    {:%, [line: Map.get(meta, :line, context.line), star_node: true],
     [StarView.Template.Node, {:%{}, [], entries}]}
  end

  def metadata(context, meta) do
    Map.merge(meta, %{file: context.file, site: context.path, namespace: context.namespace})
  end

  def error!(message, context, meta \\ %{}) do
    raise CompileError,
      file: context.file,
      line: Map.get(meta, :line, context.line),
      description: "~STAR: " <> message
  end

  def validate!(value, validator, context, meta) do
    validator.(value)
  rescue
    error in ArgumentError -> error!(Exception.message(error), context, meta)
  end

  defp require_assigns!(caller) do
    if !Macro.Env.has_var?(caller, {:assigns, nil}) do
      raise CompileError,
        file: caller.file,
        line: caller.line,
        description: "~STAR requires an assigns variable, like ~H"
    end
  end

  defp context(caller) do
    %{
      caller: caller,
      file: caller.file,
      line: caller.line + 1,
      module: caller.module,
      function: caller.function,
      path: [],
      namespace: :html
    }
  end

  defp fingerprint(source, caller),
    do: :crypto.hash(:sha256, :erlang.term_to_binary({2, caller.module, caller.function, source}))
end
