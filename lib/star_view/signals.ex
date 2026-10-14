defmodule StarView.Signals do
  @moduledoc """
  Datastar signal reading and `datastar-patch-signals` helpers.
  """

  alias Plug.Conn
  alias StarView.Constants
  alias StarView.JSON
  alias StarView.SSE

  @event_type Constants.event_type(:patch_signals)
  @datastar_key Constants.datastar_key()
  @default_only_if_missing Constants.default_patch_signals_only_if_missing()
  @default_max_bytes 1_000_000

  @doc """
  Fetches an object signal document and returns Plug's updated connection.

  Raw bodies and the `datastar` query JSON are limited to 1,000,000 bytes by
  default, configurable with `:max_bytes`. Already-parsed body params rely on
  `Plug.Parsers`'s configured length limit. Always thread the returned conn.
  """
  @spec fetch(Conn.t(), keyword()) :: {:ok, map(), Conn.t()} | {:error, term(), Conn.t()}
  def fetch(conn, opts \\ []) do
    max_bytes = max_bytes!(opts)
    fetch_signals(conn, max_bytes)
  end

  defp fetch_signals(%Conn{method: method} = conn, max_bytes) when method in ["GET", "DELETE"] do
    conn = Conn.fetch_query_params(conn)
    result = decode_query(Map.get(conn.query_params, @datastar_key), max_bytes)
    fetch_query_result(result, conn)
  end

  defp fetch_signals(%Conn{body_params: %Conn.Unfetched{}} = conn, max_bytes) do
    case Conn.read_body(conn, length: max_bytes, read_length: max_bytes) do
      {:ok, "", conn} -> {:ok, %{}, put_signals(conn, %{})}
      {:ok, body, conn} -> fetch_body_result(body, conn, max_bytes)
      {:more, _partial, conn} -> {:error, :body_too_large, conn}
      {:error, reason} -> {:error, reason, conn}
    end
  end

  defp fetch_signals(%Conn{body_params: %{"_json" => value} = params} = conn, _max_bytes)
       when map_size(params) == 1 do
    # Plug.Parsers wraps non-object JSON in this reserved key. Datastar
    # excludes underscore-prefixed signals from submitted documents.
    {:error, {:invalid_signals, value}, conn}
  end

  defp fetch_signals(%Conn{body_params: params} = conn, _max_bytes) when is_map(params),
    do: {:ok, params, conn}

  defp fetch_signals(conn, _max_bytes), do: {:error, :invalid_signals, conn}

  defp fetch_query_result({:ok, signals}, conn), do: {:ok, signals, conn}
  defp fetch_query_result({:error, reason}, conn), do: {:error, reason, conn}

  defp fetch_body_result(body, conn, max_bytes) do
    body |> decode_bounded(max_bytes) |> fetch_result(conn)
  end

  defp fetch_result({:ok, signals}, conn), do: {:ok, signals, put_signals(conn, signals)}
  defp fetch_result({:error, reason}, conn), do: {:error, reason, conn}

  defp put_signals(conn, signals) do
    params = fetched_params(conn.params)
    params = params |> Map.merge(signals) |> Map.merge(fetched_params(conn.path_params))
    %{conn | body_params: signals, params: params}
  end

  defp fetched_params(%Conn.Unfetched{}), do: %{}
  defp fetched_params(params) when is_map(params), do: params
  defp fetched_params(_params), do: %{}

  defp decode_query(nil, _max_bytes), do: {:ok, %{}}
  defp decode_query("", _max_bytes), do: {:error, :invalid_signals}
  defp decode_query(json, max_bytes) when is_binary(json), do: decode_bounded(json, max_bytes)
  defp decode_query(_json, _max_bytes), do: {:error, :invalid_signals}

  defp decode_bounded(json, max_bytes) when byte_size(json) > max_bytes,
    do: {:error, :body_too_large}

  defp decode_bounded(json, _max_bytes), do: decode_map(json)

  defp max_bytes!(opts) do
    case Keyword.get(opts, :max_bytes, @default_max_bytes) do
      value when is_integer(value) and value > 0 -> value
      _ -> raise ArgumentError, ":max_bytes must be a positive integer"
    end
  end

  @doc "Sends a plain HTTP 400 or 413 response for a signal input error before SSE starts."
  @spec send_error(Conn.t(), term()) :: Conn.t()
  def send_error(conn, reason) do
    {status, message} = input_error(reason)

    conn
    |> Conn.put_resp_content_type("text/plain")
    |> Conn.send_resp(status, message)
    |> Conn.halt()
  end

  defp input_error(:body_too_large), do: {413, "Signal payload too large"}
  defp input_error(_reason), do: {400, "Invalid signal payload"}

  @doc """
  Reads Datastar signals from a Plug connection.

  `GET` and `DELETE` requests read the `datastar` query parameter. Other
  methods read JSON from the request body unless a parser has already populated
  `conn.body_params`. For raw bodies, prefer `fetch/2` so the updated conn
  reaches subsequent plugs; this compatibility API returns only the result.
  """
  @spec read(Conn.t()) :: {:ok, map()} | {:error, term()}
  def read(%Conn{} = conn) do
    case fetch(conn) do
      {:ok, signals, _conn} -> {:ok, signals}
      {:error, reason, _conn} -> {:error, reason}
    end
  end

  @doc """
  Reads Datastar signals and raises on errors.
  """
  @spec read!(Conn.t()) :: map()
  def read!(%Conn{} = conn) do
    case read(conn) do
      {:ok, signals} -> signals
      {:error, reason} -> raise StarView.Signals.ReadError, reason: reason
    end
  end

  @doc """
  Sends a signal patch from a map.
  """
  @spec patch(Conn.t(), map(), keyword()) :: Conn.t()
  def patch(conn, signals, opts \\ []) when is_map(signals) do
    patch_raw(conn, JSON.encode!(signals), opts)
  end

  @doc """
  Sends a signal patch from a JSON string.
  """
  @spec patch_raw(Conn.t(), String.t(), keyword()) :: Conn.t()
  def patch_raw(conn, signals_json, opts \\ []) when is_binary(signals_json) do
    data_lines = data_lines(signals_json, opts)
    SSE.send!(conn, @event_type, data_lines, sse_opts(opts))
  end

  @doc """
  Removes one or more signals by setting dot-notated paths to `null`.
  """
  @spec remove_signals(Conn.t(), String.t() | [String.t()], keyword()) :: Conn.t()
  def remove_signals(conn, paths, opts \\ []) do
    patch(conn, paths_to_nil_map(List.wrap(paths)), opts)
  end

  @doc """
  Formats a signal patch without writing to a connection.
  """
  @spec format_patch(map(), keyword()) :: String.t()
  def format_patch(signals, opts \\ []) when is_map(signals) do
    format_patch_raw(JSON.encode!(signals), opts)
  end

  @doc """
  Formats a raw JSON signal patch without writing to a connection.
  """
  @spec format_patch_raw(String.t(), keyword()) :: String.t()
  def format_patch_raw(signals_json, opts \\ []) when is_binary(signals_json) do
    SSE.format_event(
      @event_type,
      data_lines(signals_json, opts),
      sse_opts(opts)
    )
  end

  @doc """
  Formats a signal removal without writing to a connection.
  """
  @spec format_remove(String.t() | [String.t()], keyword()) :: String.t()
  def format_remove(paths, opts \\ []) do
    paths
    |> List.wrap()
    |> paths_to_nil_map()
    |> format_patch(opts)
  end

  @doc false
  def data_lines(signals_json, opts \\ []) do
    only_if_missing = Keyword.get(opts, :only_if_missing, @default_only_if_missing)

    []
    |> maybe_add_only_if_missing(only_if_missing)
    |> add_signals(signals_json)
  end

  defp maybe_add_only_if_missing(lines, false), do: lines

  defp maybe_add_only_if_missing(lines, true) do
    lines ++ [Constants.dataline_literal(:only_if_missing) <> "true"]
  end

  defp add_signals(lines, signals_json) do
    lines ++
      (signals_json
       |> String.split(["\r\n", "\r", "\n"])
       |> Enum.map(&(Constants.dataline_literal(:signals) <> &1)))
  end

  defp paths_to_nil_map(paths) when is_list(paths) do
    Enum.reduce(paths, %{}, fn path, acc ->
      validate_path!(path)
      deep_merge(acc, path_to_nil_map(path))
    end)
  end

  defp path_to_nil_map(path) do
    path
    |> String.split(".")
    |> Enum.reverse()
    |> Enum.reduce(nil, fn segment, acc -> %{segment => acc} end)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      cond do
        is_nil(left_value) or is_nil(right_value) -> nil
        is_map(left_value) and is_map(right_value) -> deep_merge(left_value, right_value)
        true -> right_value
      end
    end)
  end

  defp validate_path!(path) when is_binary(path) do
    cond do
      path == "" ->
        raise ArgumentError, "signal path cannot be empty"

      String.starts_with?(path, ".") ->
        raise ArgumentError, "signal path cannot start with a dot: #{inspect(path)}"

      String.ends_with?(path, ".") ->
        raise ArgumentError, "signal path cannot end with a dot: #{inspect(path)}"

      String.contains?(path, "..") ->
        raise ArgumentError, "signal path cannot contain consecutive dots: #{inspect(path)}"

      true ->
        :ok
    end
  end

  defp validate_path!(path),
    do: raise(ArgumentError, "signal path must be a string, got: #{inspect(path)}")

  defp decode_map(json) when is_binary(json) do
    case JSON.decode(json) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, value} -> {:error, {:invalid_signals, value}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sse_opts(opts), do: Keyword.take(opts, [:event_id, :retry, :retry_duration])
end
