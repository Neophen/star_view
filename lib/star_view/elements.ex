defmodule StarView.Elements do
  @moduledoc """
  Datastar `datastar-patch-elements` helpers.
  """

  alias StarView.Constants
  alias StarView.SSE
  alias StarView.Stream.RenderState

  @event_type Constants.event_type(:patch_elements)
  @default_patch_mode Constants.default_element_patch_mode()
  @default_namespace Constants.default_namespace()
  @default_use_view_transitions Constants.default_elements_use_view_transitions()
  @valid_modes Constants.element_patch_modes()
  @valid_namespaces Constants.namespaces()
  @idempotent_modes [:outer, :inner, :replace]

  @doc """
  Sends HTML elements to the browser for DOM patching.

  ## Skipping unchanged patches

  Inside `StarView.Stream.run/2`, `only_changed: true` with an explicit `:key`
  skips a patch whose HTML, selector, mode, namespace and view-transition
  setting and SSE metadata all equal the last patch sent under that key on this stream.

      patch(conn, html, key: :orders, selector: "#orders", only_changed: true)

  Only idempotent modes (`:outer`, `:inner`, `:replace`) are accepted, since
  repeating an append, prepend, before, after or remove has a visible effect.
  The comparison uses a SHA-256 digest. Each stream tracks up to 64 keys; later
  keys always send. A new stream starts empty, and conns outside an active
  `run/2` (such as event responses) always send. `format_patch/2` ignores these
  options.

  The stream only knows what it sent, not the browser's final DOM. Any other
  element patch or removal on the same stream (including `execute_script/3`)
  clears every remembered key, so the next keyed patch sends again. Event
  responses, other streams, raw `StarView.send/4` events and browser code can
  still change the DOM unseen: use `only_changed` only for a region this stream
  owns exclusively. Give each key its own non-overlapping region; two keys that
  target the same or nested elements can skip a patch the page needs.
  """
  @spec patch(Plug.Conn.t(), iodata() | tuple() | nil, keyword()) :: Plug.Conn.t()
  def patch(conn, elements, opts \\ []) do
    data_lines = data_lines(elements, opts)
    send_patch(conn, data_lines, opts, Keyword.get(opts, :only_changed, false))
  end

  defp send_patch(conn, data_lines, opts, false),
    do: conn |> send_lines(data_lines, opts) |> RenderState.forget_all()

  defp send_patch(conn, data_lines, opts, true) do
    idempotent_mode!(opts)
    send_changed(conn, data_lines, opts, changed_key!(opts))
  end

  defp send_patch(_conn, _data_lines, _opts, _only_changed),
    do: raise(ArgumentError, ":only_changed must be a boolean")

  defp send_changed(conn, data_lines, opts, key) do
    fingerprint = fingerprint(data_lines, opts)

    if RenderState.unchanged?(conn, key, fingerprint),
      do: conn,
      else: conn |> send_lines(data_lines, opts) |> RenderState.remember(key, fingerprint)
  end

  defp send_lines(conn, data_lines, opts),
    do: SSE.send!(conn, @event_type, data_lines, sse_opts(opts))

  defp idempotent_mode!(opts) do
    mode = opts |> Keyword.get(:mode, @default_patch_mode) |> normalize_mode()

    if mode not in @idempotent_modes do
      raise ArgumentError,
            "only_changed: true supports #{inspect(@idempotent_modes)} modes, got: #{inspect(mode)}"
    end
  end

  defp changed_key!(opts) do
    case Keyword.get(opts, :key) do
      nil -> raise ArgumentError, "only_changed: true requires an explicit non-nil :key"
      key -> key
    end
  end

  defp fingerprint(data_lines, opts),
    do: :crypto.hash(:sha256, SSE.format_event(@event_type, data_lines, sse_opts(opts)))

  @doc """
  Sends an element removal patch.
  """
  @spec remove(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def remove(conn, selector, opts \\ []) when is_binary(selector) do
    patch(conn, nil, remove_opts(selector, opts))
  end

  @doc """
  Formats an element patch event without writing to a connection.
  """
  @spec format_patch(iodata() | tuple() | nil, keyword()) :: String.t()
  def format_patch(elements, opts \\ []) do
    SSE.format_event(@event_type, data_lines(elements, opts), sse_opts(opts))
  end

  @doc """
  Formats an element removal event without writing to a connection.
  """
  @spec format_remove(String.t(), keyword()) :: String.t()
  def format_remove(selector, opts \\ []) when is_binary(selector) do
    format_patch(nil, remove_opts(selector, opts))
  end

  @doc false
  def data_lines(elements, opts \\ []) do
    mode = opts |> Keyword.get(:mode, @default_patch_mode) |> normalize_mode()
    namespace = opts |> Keyword.get(:namespace, @default_namespace) |> normalize_namespace()

    use_view_transitions =
      Keyword.get(
        opts,
        :use_view_transition,
        Keyword.get(opts, :use_view_transitions, @default_use_view_transitions)
      )

    elements = if !is_nil(elements), do: to_html_string(elements)

    validate_elements!(elements, mode)

    []
    |> maybe_add_selector(Keyword.get(opts, :selector))
    |> maybe_add_mode(mode)
    |> maybe_add_view_transition(use_view_transitions)
    |> maybe_add_namespace(namespace)
    |> add_elements(elements)
  end

  defp maybe_add_selector(lines, nil), do: lines
  defp maybe_add_selector(lines, ""), do: lines

  defp maybe_add_selector(lines, selector) when is_binary(selector) do
    lines ++ [Constants.dataline_literal(:selector) <> selector]
  end

  defp maybe_add_mode(lines, @default_patch_mode), do: lines

  defp maybe_add_mode(lines, mode) do
    lines ++ [Constants.dataline_literal(:mode) <> Atom.to_string(mode)]
  end

  defp maybe_add_namespace(lines, @default_namespace), do: lines

  defp maybe_add_namespace(lines, namespace) do
    lines ++ [Constants.dataline_literal(:namespace) <> Atom.to_string(namespace)]
  end

  defp maybe_add_view_transition(lines, false), do: lines

  defp maybe_add_view_transition(lines, true) do
    lines ++ [Constants.dataline_literal(:use_view_transition) <> "true"]
  end

  defp add_elements(lines, nil), do: lines

  defp add_elements(lines, elements) do
    lines ++
      (elements
       |> String.split(["\r\n", "\r", "\n"])
       |> Enum.map(&(Constants.dataline_literal(:elements) <> &1)))
  end

  defp remove_opts(selector, opts) do
    opts
    |> Keyword.put(:selector, selector)
    |> Keyword.put(:mode, :remove)
  end

  defp validate_elements!(nil, :remove), do: :ok

  defp validate_elements!(nil, _mode),
    do: raise(ArgumentError, "elements are required unless mode is :remove")

  defp validate_elements!(_elements, _mode), do: :ok

  defp normalize_mode(mode) when is_atom(mode) and mode in @valid_modes, do: mode

  defp normalize_mode(mode) when is_binary(mode) do
    mode
    |> String.to_existing_atom()
    |> normalize_mode()
  rescue
    ArgumentError -> raise_invalid_mode(mode)
  end

  defp normalize_mode(mode), do: raise_invalid_mode(mode)

  defp raise_invalid_mode(mode) do
    raise ArgumentError,
          "invalid element patch mode #{inspect(mode)}; expected one of #{inspect(@valid_modes)}"
  end

  defp normalize_namespace(namespace) when is_atom(namespace) and namespace in @valid_namespaces,
    do: namespace

  defp normalize_namespace(namespace) when is_binary(namespace) do
    namespace
    |> String.to_existing_atom()
    |> normalize_namespace()
  rescue
    ArgumentError -> raise_invalid_namespace(namespace)
  end

  defp normalize_namespace(namespace), do: raise_invalid_namespace(namespace)

  defp raise_invalid_namespace(namespace) do
    raise ArgumentError,
          "invalid element namespace #{inspect(namespace)}; expected one of #{inspect(@valid_namespaces)}"
  end

  defp to_html_string(html) when is_binary(html), do: html
  defp to_html_string({:safe, iodata}), do: IO.iodata_to_binary(iodata)
  defp to_html_string(iodata) when is_list(iodata), do: IO.iodata_to_binary(iodata)

  defp to_html_string(other) do
    if Code.ensure_loaded?(:"Elixir.Phoenix.HTML.Safe") do
      other
      |> then(&apply(:"Elixir.Phoenix.HTML.Safe", :to_iodata, [&1]))
      |> IO.iodata_to_binary()
    else
      raise ArgumentError,
            "expected HTML as a binary, iodata, {:safe, iodata}, or Phoenix.HTML.Safe value"
    end
  end

  defp sse_opts(opts), do: Keyword.take(opts, [:event_id, :retry, :retry_duration])
end
