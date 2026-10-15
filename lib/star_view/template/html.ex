defmodule StarView.Template.HTML do
  @moduledoc false

  # Escaping for `StarView.Template` rendering. Dynamic values go through the
  # public `Phoenix.HTML` API; attribute names are validated here because
  # `Phoenix.HTML.attributes_escape/1` only entity-escapes keys, which does not
  # stop whitespace or `=` from forging extra attributes.

  # HTML attribute-name rule (no whitespace, quotes, `<`, `>`, `/`, `=` or
  # controls), additionally rejecting `&` and backticks.
  alias StarView.Template.Runtime

  @attribute_name ~r/\A[^\s"'<>\/=`&\x00-\x1F\x7F]+\z/u
  @delimiters ["\"", "'"]
  @nested_prefixes ["aria", "data", "phx"]

  @doc false
  def escape(value) do
    Runtime.reject_legacy!(value)
    {:safe, iodata} = phoenix_html!(:html_escape, [value])
    iodata
  end

  @doc false
  def attributes(attrs) when is_list(attrs), do: Enum.map(attrs, &attribute/1)

  def attributes(attrs),
    do: raise(ArgumentError, "expected template attributes as a list, got: #{inspect(attrs)}")

  @doc false
  def attribute({:static, name, nil, _delimiter}), do: [?\s, attribute_name!(name)]

  def attribute({:static, name, raw, delimiter})
      when is_binary(raw) and delimiter in @delimiters do
    if String.contains?(raw, delimiter) do
      raise ArgumentError,
            "static attribute #{inspect(name)} contains its own delimiter #{delimiter}"
    end

    [?\s, attribute_name!(name), ?=, delimiter, raw, delimiter]
  end

  def attribute({:dynamic, _name, %StarView.Template{}}),
    do: raise(ArgumentError, "a StarView.Template cannot be used as an attribute value")

  def attribute({:dynamic, name, value}), do: dynamic(attribute_name!(name), value)
  def attribute({:spread, attrs}), do: attrs |> flatten_spread() |> Enum.map(&pair/1)

  def attribute(other), do: raise(ArgumentError, "invalid template attribute: #{inspect(other)}")

  @doc false
  def flatten_spread(attrs) when is_list(attrs) or is_map(attrs),
    do: attrs |> Enum.to_list() |> Enum.flat_map(&spread_entry/1)

  def flatten_spread(attrs),
    do:
      raise(ArgumentError, "expected spread attributes as a list or map, got: #{inspect(attrs)}")

  # HEEx encodes `class` and `style` itself and always emits them.
  defp dynamic("class", value), do: [~s( class="), class_value(value), ?"]
  defp dynamic("style", value), do: [~s( style="), empty_value(value), ?"]

  defp dynamic(name, value) when name in @nested_prefixes and is_list(value),
    do: name |> nested(value) |> Enum.map(&pair/1)

  defp dynamic(name, value), do: encoded_pair(name, value)

  defp spread_entry({key, value}), do: expand(spread_key!(key), value)

  defp spread_entry(other),
    do: raise(ArgumentError, "invalid spread attribute entry: #{inspect(other)}")

  defp expand(name, value) when name in @nested_prefixes and is_list(value),
    do: nested(name, value)

  defp expand(name, value), do: [{name, value}]

  defp nested(prefix, entries), do: Enum.flat_map(entries, &nested_entry(prefix, &1))

  defp nested_entry(prefix, {key, value}) when is_list(value),
    do: nested(prefix <> "-" <> nested_key!(key), value)

  defp nested_entry(prefix, {key, value}), do: [{prefix <> "-" <> nested_key!(key), value}]

  defp nested_entry(prefix, other),
    do: raise(ArgumentError, "invalid #{prefix} attribute entry: #{inspect(other)}")

  defp pair({_name, %StarView.Template{}}),
    do: raise(ArgumentError, "a StarView.Template cannot be used as an attribute value")

  defp pair({name, value}) do
    encoded_pair(attribute_name!(name), value)
  end

  defp encoded_pair(_name, %StarView.Template{}),
    do: raise(ArgumentError, "a StarView.Template cannot be used as an attribute value")

  defp encoded_pair(_name, value) when value in [nil, false], do: []
  defp encoded_pair(name, true), do: [?\s, name]

  defp encoded_pair(name, value) when is_binary(value), do: [?\s, name, ?=, ?", escape(value), ?"]

  defp encoded_pair(name, value) do
    Runtime.reject_legacy!(value)
    {:safe, iodata} = phoenix_html!(:attributes_escape, [[{name, value}]])
    iodata
  end

  # HEEx's spread keeps atom keys verbatim; only nested keys are dasherized.
  defp spread_key!(key) when is_atom(key), do: Atom.to_string(key)
  defp spread_key!(key) when is_binary(key), do: key

  defp spread_key!(key),
    do:
      raise(
        ArgumentError,
        "spread attribute names must be atoms or strings, got: #{inspect(key)}"
      )

  defp nested_key!(key) when is_atom(key), do: key |> Atom.to_string() |> String.replace("_", "-")
  defp nested_key!(key) when is_binary(key), do: key

  defp nested_key!(key),
    do:
      raise(
        ArgumentError,
        "nested attribute names must be atoms or strings, got: #{inspect(key)}"
      )

  @doc false
  def attribute_name!(name) when is_binary(name) and byte_size(name) > 0 do
    if !valid_attribute_name?(name, ascii_attribute_name?(name)) do
      raise ArgumentError, "invalid attribute name: #{inspect(name)}"
    end

    name
  end

  def attribute_name!(name), do: raise(ArgumentError, "invalid attribute name: #{inspect(name)}")

  # Almost every rendered name is ASCII. Avoid entering the regular expression
  # engine for each attribute while preserving its Unicode/invalid-UTF8 rules.
  defp ascii_attribute_name?(<<>>), do: true

  defp ascii_attribute_name?(<<character, rest::binary>>)
       when character in 33..126 and character not in ~c"\"'<>/=`&",
       do: ascii_attribute_name?(rest)

  defp ascii_attribute_name?(<<character, _rest::binary>>) when character < 128, do: false
  defp ascii_attribute_name?(_name), do: :unicode

  defp valid_attribute_name?(name, :unicode), do: Regex.match?(@attribute_name, name)
  defp valid_attribute_name?(_name, valid?), do: valid?

  defp class_value(list) when is_list(list),
    do: list |> class_list([]) |> IO.iodata_to_binary() |> escape()

  defp class_value(value), do: empty_value(value)

  defp empty_value(value) when value in [nil, false, true], do: ""
  defp empty_value(value), do: escape(value)

  defp class_list([], acc), do: acc
  defp class_list([falsy | tail], acc) when falsy in [nil, false], do: class_list(tail, acc)

  defp class_list([head | tail], acc) when is_list(head),
    do: class_list(tail, class_list(head, acc))

  defp class_list([head | tail], []), do: class_list(tail, class_name(head))
  defp class_list([head | tail], acc), do: class_list(tail, [acc, ?\s, class_name(head)])

  defp class_name(value), do: value |> Runtime.reject_legacy!() |> to_string()

  defp phoenix_html!(function, args) do
    if !function_exported?(Phoenix.HTML, function, length(args)) and
         !Code.ensure_loaded?(Phoenix.HTML) do
      raise "StarView.Template needs the :phoenix_html dependency (included with " <>
              ":phoenix_live_view) to render dynamic values and attributes"
    end

    apply(Phoenix.HTML, function, args)
  end
end
