defmodule StarView.Actions do
  @moduledoc """
  Datastar action expression helpers.

  These helpers generate strings for `data-on:*` attributes:

      <button data-on:click={StarView.Actions.post(MyAppWeb.CounterController, "increment")}>

  Event names and literal module overrides are percent-encoded as one URL path
  segment. The default dynamic module signal is encoded in the browser too.
  Empty and exact dot segments are rejected because browsers normalize them.

  A `:prefix` must be a local application path containing no dot segments,
  backslashes, queries, fragments, controls, or URL scheme. Safe relative paths
  such as `"admin"` are normalized to `"/admin"` for compatibility.
  A dynamic `:module` override is a literal value, never JavaScript source.
  Custom `$`-prefixed overrides raise; only `"$_star_view_module"` retains the
  default dynamic signal behavior. Action strings use JSON double quotes.
  """

  @verbs ~w(get post put patch delete)a

  for verb <- @verbs do
    verb_string = Atom.to_string(verb)

    @doc """
    Generates a `@#{verb_string}(...)` Datastar action expression.
    """
    def unquote(verb)(module_or_event, event_or_opts \\ [])

    def unquote(verb)(module, event) when is_atom(module) and is_binary(event) do
      action(unquote(verb_string), module, event, [])
    end

    def unquote(verb)(event, opts) when is_binary(event) and is_list(opts) do
      dynamic_action(unquote(verb_string), event, opts)
    end

    def unquote(verb)(module, event, opts)
        when is_atom(module) and is_binary(event) and is_list(opts) do
      action(unquote(verb_string), module, event, opts)
    end
  end

  @doc """
  Encodes an Elixir module name for URL path usage.
  """
  @spec encode_module(module()) :: String.t()
  def encode_module(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.map_join("-", &Macro.underscore/1)
  end

  @doc """
  Decodes a URL-safe module name into an existing Elixir module.
  """
  @spec decode_module(String.t()) :: {:ok, module()} | :error
  def decode_module(encoded) when is_binary(encoded) do
    module =
      encoded
      |> String.split("-")
      |> Enum.map_join(".", &Macro.camelize/1)

    {:ok, String.to_existing_atom("Elixir." <> module)}
  rescue
    ArgumentError -> :error
  end

  @doc false
  def dom_id("#" <> _ = id), do: id
  def dom_id(id) when is_binary(id), do: "#" <> id

  defp action(verb, module, event, opts) do
    path = dispatch_base(opts) <> "/" <> encode_segment!(encode_module(module))
    "@#{verb}(#{javascript_string(path <> "/" <> encode_segment!(event))})"
  end

  defp dynamic_action(verb, event, opts) do
    base = dispatch_base(opts)
    event = encode_segment!(event)
    "@#{verb}(#{dynamic_path(base, event, Keyword.get(opts, :module, :dynamic))})"
  end

  defp dynamic_path(base, event, module) when module in [:dynamic, "$_star_view_module"] do
    javascript_string(base <> "/") <>
      " + " <>
      dynamic_module_segment() <>
      " + " <> javascript_string("/" <> event)
  end

  defp dynamic_path(_base, _event, "$" <> _module) do
    raise ArgumentError,
          "custom $-prefixed module overrides are no longer supported; use the default module signal or a literal module name"
  end

  defp dynamic_path(base, event, module) when is_binary(module) do
    javascript_string(base <> "/" <> encode_segment!(module) <> "/" <> event)
  end

  defp dynamic_path(_base, _event, module) do
    raise ArgumentError, ":module must be a literal module string, got: #{inspect(module)}"
  end

  defp dispatch_base(opts), do: normalize_prefix(Keyword.get(opts, :prefix, "")) <> "/ds"

  defp normalize_prefix(prefix) when prefix in [nil, ""], do: ""

  defp normalize_prefix(prefix) when is_binary(prefix) do
    prefix = local_prefix!(prefix)
    decoded = URI.decode(prefix)

    if invalid_prefix?(prefix, decoded) do
      raise ArgumentError, ":prefix must be a valid local absolute application path"
    end

    String.trim_trailing(prefix, "/")
  end

  defp normalize_prefix(_prefix) do
    raise ArgumentError, ":prefix must be a valid local absolute application path"
  end

  defp local_prefix!("/" <> _ = prefix), do: prefix

  defp local_prefix!(prefix) do
    if String.valid?(prefix) and String.match?(prefix, ~r/\A[A-Za-z][A-Za-z0-9+.-]*:/) do
      raise ArgumentError, ":prefix must be a local application path"
    end

    "/" <> prefix
  end

  defp invalid_prefix?(prefix, decoded) do
    not String.valid?(prefix) or not String.valid?(decoded) or
      String.contains?(String.replace(prefix, ~r/%[0-9A-Fa-f]{2}/, ""), "%") or
      unsafe_prefix?(prefix) or unsafe_prefix?(decoded)
  end

  defp unsafe_prefix?(prefix) do
    not String.starts_with?(prefix, "/") or String.starts_with?(prefix, "//") or
      String.contains?(prefix, ["\\", "?", "#"]) or
      String.match?(prefix, ~r/[\x00-\x1F\x7F]/u) or
      Enum.any?(String.split(prefix, "/"), &(&1 in [".", ".."]))
  end

  # URL-safety rules adapted from dstar (MIT), Rico Trevisan, 2025.
  defp encode_segment!(segment) do
    if segment in ["", ".", ".."] or not String.valid?(segment) do
      raise ArgumentError, "path segment must be valid UTF-8 and not empty or a dot segment"
    end

    URI.encode(segment, &segment_char?/1)
  end

  defp segment_char?(char) do
    char in ?a..?z or char in ?A..?Z or char in ?0..?9 or char in [?-, ?_, ?~]
  end

  defp dynamic_module_segment() do
    "((segment) => { if (typeof segment !== 'string' || segment === '' || segment === '.' || segment === '..') " <>
      "throw new TypeError('invalid StarView module segment'); return encodeURIComponent(segment)" <>
      ".replace(/[!'()*\\.]/g, char => '%' + char.charCodeAt(0).toString(16).toUpperCase()) })($_star_view_module)"
  end

  defp javascript_string(value) do
    value
    |> StarView.JSON.encode!()
    |> String.replace("\u2028", "\\u2028")
    |> String.replace("\u2029", "\\u2029")
  end
end
