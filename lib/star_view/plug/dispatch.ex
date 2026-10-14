defmodule StarView.Plug.Dispatch do
  @moduledoc """
  Allowlisted Datastar event dispatch plug.

  Configure it with the modules that are allowed to receive events:

      post "/ds/:module/:event", StarView.Plug.Dispatch,
        modules: [MyAppWeb.CounterEvents]

  Handler modules must export `handle_event(conn, event, signals)`.
  """

  @behaviour Plug

  import Plug.Conn

  alias StarView.Actions
  alias StarView.Signals

  @impl Plug
  def init(opts) do
    modules = Keyword.fetch!(opts, :modules)

    %{
      lookup: Map.new(modules, fn module -> {Actions.encode_module(module), module} end),
      start?: Keyword.get(opts, :start, true)
    }
  end

  @impl Plug
  def call(conn, %{lookup: lookup, start?: start?}) do
    conn = fetch_query_params(conn)
    module_param = conn.path_params["module"] || conn.params["module"]
    event = conn.path_params["event"] || conn.params["event"]

    with {:ok, module} <- fetch_module(lookup, module_param),
         true <- Code.ensure_loaded?(module) and function_exported?(module, :handle_event, 3),
         {:ok, signals, conn} <- Signals.fetch(conn) do
      conn
      |> maybe_start(start?)
      |> StarView.Dispatch.invoke(module, event, signals, :conn_first)
    else
      {:error, reason, conn} ->
        Signals.send_error(conn, reason)

      _ ->
        send_error(conn, 404, "Not found")
    end
  end

  defp fetch_module(_lookup, nil), do: :error
  defp fetch_module(lookup, module_param), do: Map.fetch(lookup, module_param)

  defp maybe_start(conn, true), do: StarView.start(conn)
  defp maybe_start(conn, false), do: conn

  defp send_error(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
  end
end
