defmodule StarView.Test do
  @moduledoc """
  Assertions for StarView SSE responses in `Plug.Test` / `Phoenix.ConnTest`
  tests. Chunked SSE bodies accumulate on the test adapter; these helpers
  parse them back into events.

      conn = Plug.Conn.put_req_header(conn, "content-type", "application/json")
      conn = post(conn, "/ds/my_app_web-counter_controller/increment", StarView.JSON.encode!(%{count: 0}))
      assert_patched_signals(conn, %{count: 1})
      assert_patched_element(conn, "#history")
  """

  import ExUnit.Assertions, only: [assert: 2]

  alias StarView.JSON

  @doc """
  Parses the SSE events from a conn (or raw body string) into a list of
  `%{type: String.t() | nil, data: [String.t()]}`.

  This parser understands StarView's own SSE output format (`event: ` /
  `data: ` with a trailing space, LF line endings) — it is not a
  general-purpose SSE parser.
  """
  def sse_events(%Plug.Conn{} = conn), do: conn |> chunked_body() |> sse_events()

  def sse_events(body) when is_binary(body) do
    body
    |> String.split("\n\n", trim: true)
    |> Enum.map(&parse_event/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Combines all emitted signal patch documents, including `null` removals.
  This inspects writes, not the browser's final state: it does not apply
  `onlyIfMissing` against initial signals or remove null-valued keys.
  """
  def patched_signals(conn) do
    conn
    |> sse_events()
    |> Enum.filter(&(&1.type == "datastar-patch-signals"))
    |> Enum.reduce(%{}, &merge_signal_event/2)
  end

  defp merge_signal_event(%{data: data}, acc) do
    json = data |> Enum.flat_map(&signal_fragment/1) |> Enum.join("\n")
    deep_merge(acc, JSON.decode!(json))
  end

  defp signal_fragment("signals " <> json), do: [json]
  defp signal_fragment(_line), do: []

  @doc """
  Asserts a top-level subset of emitted signals. Nested values compare exactly.
  Keys may be atoms
  or strings; values compare against the JSON-decoded patch.
  Returns the conn for piping.
  """
  def assert_patched_signals(conn, expected) when is_map(expected) do
    actual = patched_signals(conn)
    expected = expected |> JSON.encode!() |> JSON.decode!()

    for {key, value} <- expected do
      assert Map.has_key?(actual, key) and Map.get(actual, key) == value,
             "expected signal #{inspect(key)} to be patched to #{inspect(value)}, " <>
               "got #{inspect(Map.get(actual, key))}. All patched signals: #{inspect(actual)}"
    end

    conn
  end

  @doc """
  Asserts a `datastar-patch-elements` event targets `target` — either via
  an explicit `selector` line or via an `id` attribute in the patched HTML
  (pass the target as `"#the-id"` in both cases).
  Returns the conn for piping.
  """
  def assert_patched_element(conn, "#" <> _ = target) do
    events =
      conn
      |> sse_events()
      |> Enum.filter(&(&1.type == "datastar-patch-elements"))

    id = String.trim_leading(target, "#")

    found = Enum.any?(events, &targets_element?(&1, target, id))

    assert found,
           "no datastar-patch-elements event targeting #{inspect(target)}. " <>
             "Element events: #{inspect(events)}"

    conn
  end

  def assert_patched_element(_conn, target) do
    raise ArgumentError,
          "assert_patched_element/2 only supports \"#id\" targets, got: #{inspect(target)}"
  end

  defp targets_element?(%{data: data}, target, id) do
    Enum.any?(data, &targets_line?(&1, target, id))
  end

  defp targets_line?("selector " <> selector, target, _id), do: selector == target

  defp targets_line?("elements " <> html, _target, id) do
    Regex.match?(~r/\sid\s*=\s*(["'])#{Regex.escape(id)}\1/u, html)
  end

  defp targets_line?(_line, _target, _id), do: false

  # On the Plug test adapter, chunked writes accumulate in the adapter state,
  # not in `conn.resp_body` — read whichever holds the body.
  defp chunked_body(%Plug.Conn{adapter: {Plug.Adapters.Test.Conn, %{chunks: chunks}}})
       when is_binary(chunks), do: chunks

  defp chunked_body(%Plug.Conn{resp_body: body}) when is_binary(body), do: body
  defp chunked_body(%Plug.Conn{}), do: ""

  defp parse_event(block) do
    lines = String.split(block, "\n", trim: true)

    type =
      Enum.find_value(lines, fn
        "event: " <> type -> type
        _ -> nil
      end)

    data = for "data: " <> data <- lines, do: data

    if type != nil or data != [], do: %{type: type, data: data}
  end

  defp deep_merge(m1, m2) when is_map(m1) and is_map(m2) do
    Map.merge(m1, m2, fn _key, v1, v2 -> deep_merge(v1, v2) end)
  end

  defp deep_merge(_v1, v2), do: v2
end
