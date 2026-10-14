defmodule StarView.SSE do
  @moduledoc """
  Plug-based Datastar Server-Sent Event generator.

  This module is the Elixir equivalent of the SDK ADR's
  `SSE` namespace.
  """

  alias Plug.Conn
  alias StarView.Constants

  @default_sse_retry_duration Constants.default_sse_retry_duration()

  @doc """
  Starts an SSE response.

  It sets the required Datastar/SSE headers and starts a chunked `200` response.
  `Connection: keep-alive` is only set for HTTP/1.1 connections when the Plug
  adapter exposes the request protocol.
  """
  @spec start(Conn.t()) :: Conn.t()
  def start(%Conn{} = conn) do
    conn
    |> Conn.put_resp_content_type("text/event-stream")
    |> Conn.put_resp_header("cache-control", "no-cache")
    |> maybe_put_http1_connection_header()
    |> Conn.send_chunked(200)
  end

  @doc """
  Sends a raw SSE event.
  """
  @spec send(Conn.t(), String.t(), [String.t()] | String.t(), keyword()) ::
          {:ok, Conn.t()} | {:error, term()}
  def send(%Conn{} = conn, event_type, data_lines, opts \\ [])
      when is_binary(event_type) and (is_list(data_lines) or is_binary(data_lines)) do
    data_lines = List.wrap(data_lines)
    content = format_event(event_type, data_lines, opts)

    write_chunk(conn, content)
  end

  defp write_chunk(conn, content) do
    Conn.chunk(conn, content)
  rescue
    error in ArgumentError -> {:error, error}
  end

  @doc """
  Sends a raw SSE event and raises on failure.
  """
  @spec send!(Conn.t(), String.t(), [String.t()] | String.t(), keyword()) :: Conn.t()
  def send!(%Conn{} = conn, event_type, data_lines, opts \\ []) do
    case send(conn, event_type, data_lines, opts) do
      {:ok, conn} -> conn
      {:error, reason} -> raise StarView.SSE.TransportError, reason: reason, conn: conn
    end
  end

  @doc """
  Formats a raw SSE event.
  """
  @spec format_event(String.t(), [String.t()] | String.t(), keyword()) :: String.t()
  def format_event(event_type, data_lines, opts \\ [])
      when is_binary(event_type) and (is_list(data_lines) or is_binary(data_lines)) do
    data_lines = List.wrap(data_lines)
    retry_duration = Keyword.get(opts, :retry_duration, Keyword.get(opts, :retry))

    [
      "event: ",
      strip_line_breaks(event_type),
      "\n",
      optional_id(opts[:event_id]),
      optional_retry(retry_duration),
      data_lines |> Enum.flat_map(&split_data_value/1) |> Enum.map(&["data: ", &1, "\n"]),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  @doc """
  Checks whether a chunked SSE connection still accepts writes.
  """
  @spec check_connection(Conn.t()) :: {:ok, Conn.t()} | {:error, Conn.t()}
  def check_connection(%Conn{} = conn) do
    case Conn.chunk(conn, ": \n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, conn}
    end
  rescue
    ArgumentError -> {:error, conn}
  end

  defp optional_id(nil), do: []
  defp optional_id(""), do: []
  defp optional_id(event_id), do: ["id: ", strip_line_breaks(event_id), "\n"]

  defp optional_retry(nil), do: []
  defp optional_retry(@default_sse_retry_duration), do: []
  defp optional_retry(retry), do: ["retry: ", strip_line_breaks(retry), "\n"]

  # CR, LF and CRLF are SSE line terminators. Re-prefix multiline data and
  # strip terminators from single-valued fields so values cannot forge frames.
  defp split_data_value(value) when is_binary(value),
    do: String.split(value, ["\r\n", "\r", "\n"])

  defp split_data_value(value),
    do: raise(ArgumentError, "SSE data lines must be strings, got: #{inspect(value)}")

  defp strip_line_breaks(value), do: value |> to_string() |> String.replace(["\r", "\n"], "")

  defp maybe_put_http1_connection_header(%Conn{private: private} = conn) do
    case private[:star_view_http_version] || adapter_http_protocol(conn) do
      :http1 -> Conn.put_resp_header(conn, "connection", "keep-alive")
      :"HTTP/1.1" -> Conn.put_resp_header(conn, "connection", "keep-alive")
      "HTTP/1.1" -> Conn.put_resp_header(conn, "connection", "keep-alive")
      _ -> conn
    end
  end

  defp adapter_http_protocol(%Conn{adapter: {adapter, payload}}) do
    if function_exported?(adapter, :get_http_protocol, 1) do
      apply(adapter, :get_http_protocol, [payload])
    end
  end
end
