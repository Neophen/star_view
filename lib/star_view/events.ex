defmodule StarView.Events do
  @moduledoc """
  Opt-in event contracts derived from actual `handle_event/3` clauses.

  Enable with `checked_events: true` on `use StarView`, `StarView.Page` or
  `StarView.Component`. Each named clause must use a literal event string and
  a literal HTTP method in its conn pattern. Wildcard clauses are fallbacks,
  not additional public events. There is no separate event registration list.

  Literal local request helpers in `~STAR` are checked when the module finishes
  compiling. Both dispatchers reject unknown events and wrong methods before
  starting SSE. Input validation and authorization remain the handler's job.
  """

  alias StarView.Events.Definitions
  alias StarView.Events.References

  @doc false
  def setup(opts, kind) do
    case Keyword.get(opts, :checked_events, false) do
      true -> quote do: use(StarView.Events, kind: unquote(kind))
      false -> quote do: :ok
      _value -> raise ArgumentError, ":checked_events must be a literal boolean"
    end
  end

  @doc false
  defmacro __using__(opts) do
    kind = Keyword.fetch!(opts, :kind)

    quote do
      Module.register_attribute(__MODULE__, :star_view_event_refs, accumulate: true)
      @star_view_event_kind unquote(kind)
      @before_compile StarView.Events
      @on_definition {StarView.Events, :on_definition}
      @after_compile {StarView.Events, :after_compile}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    registry = Definitions.registry!(env)
    refs = Module.get_attribute(env.module, :star_view_event_refs)
    References.validate!(refs, registry)
    Module.put_attribute(env.module, :star_view_events_finalized, true)

    quote do
      @doc false
      def __star_view_events__(), do: unquote(Macro.escape(registry))
    end
  end

  @doc false
  def on_definition(env, _kind, :handle_event, args, _guards, _body) when length(args) == 3 do
    if Module.get_attribute(env.module, :star_view_events_finalized) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "checked handle_event/3 clauses must be defined before before_compile hooks run"
    end
  end

  def on_definition(_env, _kind, _name, _args, _guards, _body), do: :ok

  @doc false
  def after_compile(env, _bytecode) do
    if map_size(env.module.__star_view_events__()) > 0 and
         not function_exported?(env.module, :handle_event, 3) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "checked handle_event/3 was removed after its event contract was generated"
    end
  end

  @doc """
  Checks a request against an opt-in contract before SSE starts.

  Unchecked modules retain their existing behavior. Returns `:ok` or
  `{:error, conn}` with a halted HTTP 404/405 response.
  """
  def validate_request(conn, module, event) do
    case check(module, event, conn.method) do
      :ok -> :ok
      {:error, :unknown_event} -> {:error, reject(conn, 404, "Not found")}
      {:error, {:method, methods}} -> {:error, reject_method(conn, methods)}
    end
  end

  @doc false
  def check(module, event, method) do
    if function_exported?(module, :__star_view_events__, 0),
      do: check_registry(module.__star_view_events__(), event, method),
      else: :ok
  end

  @doc false
  def check_registry(registry, event, method) do
    case Map.fetch(registry, event) do
      :error -> {:error, :unknown_event}
      {:ok, methods} -> check_method(method in methods, methods)
    end
  end

  defp check_method(true, _methods), do: :ok
  defp check_method(false, methods), do: {:error, {:method, methods}}

  defp reject_method(conn, methods) do
    conn
    |> Plug.Conn.put_resp_header("allow", Enum.join(methods, ", "))
    |> reject(405, "Method not allowed")
  end

  defp reject(conn, status, message),
    do: conn |> Plug.Conn.send_resp(status, message) |> Plug.Conn.halt()
end
