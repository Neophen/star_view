defmodule StarView.Plug.RenameCsrfParam do
  @moduledoc """
  Copies a Datastar CSRF signal into `_csrf_token` for `Plug.CSRFProtection`.

  POST/PUT/PATCH signals arrive in parsed body params. GET/DELETE signals
  arrive in the JSON `datastar` query parameter. Existing body `_csrf_token`
  values take precedence; a query `_csrf_token` cannot suppress a valid body
  or Datastar token. Tokens in GET/DELETE URLs should be redacted from logs.
  Sending an `x-csrf-token` header does not remove the signal from the query;
  also exclude that signal from URL-based requests if using headers instead.

  If the body is still unfetched, query/params tokens are copied to the request
  header instead of body params so later signal fetching can consume the raw
  body. An explicit `x-csrf-token` header is preserved.

  Add it before `:protect_from_forgery` when using Datastar form mode:

      plug StarView.Plug.RenameCsrfParam
      plug :protect_from_forgery
  """

  @behaviour Plug

  @impl Plug
  def init(opts) do
    %{
      from: Keyword.get(opts, :from, "csrf"),
      datastar_param: Keyword.get(opts, :datastar_param, "datastar")
    }
  end

  @impl Plug
  def call(conn, %{from: from, datastar_param: datastar_param}) do
    conn = Plug.Conn.fetch_query_params(conn)
    copy_token(conn, body_params(conn), from, datastar_param)
  end

  defp copy_token(conn, %{"_csrf_token" => _token}, _from, _datastar_param), do: conn

  defp copy_token(conn, body, from, datastar_param) do
    case source_token(conn, body, from, datastar_param) do
      {:ok, token} -> put_token(conn, body, token)
      :error -> conn
    end
  end

  defp put_token(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn, _body, token),
    do: put_header_token(conn, token, Plug.Conn.get_req_header(conn, "x-csrf-token"))

  defp put_token(conn, body, token),
    do: %{conn | body_params: Map.put(body, "_csrf_token", token)}

  defp put_header_token(conn, token, []) when is_binary(token),
    do: Plug.Conn.put_req_header(conn, "x-csrf-token", token)

  defp put_header_token(conn, _token, _existing), do: conn

  defp source_token(conn, body, from, datastar_param) do
    with :error <- Map.fetch(body, from),
         :error <- query_token(conn.query_params, from, datastar_param) do
      Map.fetch(conn.params, from)
    end
  end

  defp query_token(query_params, from, datastar_param) do
    query_params |> Map.get(datastar_param) |> decode_token(from)
  end

  # Query-token handling adapted from dstar (MIT), Rico Trevisan, 2025.
  defp decode_token(json, from) when is_binary(json) and byte_size(json) <= 1_000_000 do
    case StarView.JSON.decode(json) do
      {:ok, %{^from => token}} -> {:ok, token}
      _ -> :error
    end
  end

  defp decode_token(_json, _from), do: :error

  defp body_params(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body_params(conn), do: conn.body_params
end
