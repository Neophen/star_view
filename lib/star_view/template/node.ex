defmodule StarView.Template.Node do
  @moduledoc """
  One node of a `StarView.Template` tree.

  | Kind | Fields | Rendering |
  | --- | --- | --- |
  | `:text` | `value` | Trusted static HTML source, emitted verbatim |
  | `:value` | `value` | HTML-escaped with `Phoenix.HTML`; a nested `StarView.Template` renders structurally |
  | `:element` | `tag`, `attrs`, `children` | A normal HTML element |
  | `:branch` | `key`, `children` | The chosen branch; `key` identifies which one |
  | `:keyed` | `children` | `:fragment` items, each with a unique `key` |
  | `:fragment` | `children`, optional `key` | Its children |
  | `:component` | `value` | A native `StarView.Template`; legacy HEEx results are rejected |

  `:text` values and `{:static, ...}` attribute values are compiler output and
  must already be entity-escaped source. They are never escaped again.

  Compiled branch/collection children may hold internal programs before
  materialization. `StarView.Template.nodes/1` expands those into ordinary nodes.

  ## Element meta

    * `:void?` - `true` for void elements such as `<br>`; they render no
      closing tag and must have no children.
    * `:namespace` - `:svg` or `:mathml` for foreign elements; defaults to HTML.
    * `:browser_owned?` - `true` when browser code (a Rocket host, an editor)
      manages the element's descendants. Diffs never target those descendants.

  Other meta (dependencies, source location) is free-form and ignored by
  rendering. Do not store a conn in meta.

  ## Attributes

    * `{:static, name, raw_value, delimiter}` - `raw_value` is entity-escaped
      source and `delimiter` is `"\\""` or `"'"`. A `nil` value renders a bare
      boolean attribute.
    * `{:dynamic, name, value}` - escaped like HEEx `name={value}`: `true`
      renders a bare attribute, `nil` and `false` omit it, `class` accepts
      lists, and `class`/`style` are always emitted.
    * `{:spread, list_or_map}` - escaped like HEEx `{@rest}`.

  Dynamic and spread names are validated before rendering. Names containing
  whitespace, quotes, `<`, `>`, `/`, `=`, `&` or backticks raise.
  """

  @type kind :: :text | :value | :element | :branch | :keyed | :fragment | :component

  @type attr ::
          {:static, String.t(), String.t() | nil, String.t() | nil}
          | {:dynamic, String.t(), term()}
          | {:spread, keyword() | map()}

  @type child :: t() | StarView.Template.Program.t()

  @type t :: %__MODULE__{
          kind: kind(),
          tag: String.t() | nil,
          value: term(),
          key: term(),
          attrs: [attr()],
          children: [child()],
          meta: map()
        }

  defstruct kind: nil, tag: nil, value: nil, key: nil, attrs: [], children: [], meta: %{}

  @doc "Builds a `:text` node from trusted, already-escaped HTML source."
  @spec text(String.t()) :: t()
  def text(html) when is_binary(html), do: %__MODULE__{kind: :text, value: html}

  @doc "Builds a `:value` node."
  @spec value(term(), map()) :: t()
  def value(value, meta \\ %{}), do: %__MODULE__{kind: :value, value: value, meta: meta}

  @doc "Builds an `:element` node."
  @spec element(String.t(), [attr()], [child()], map()) :: t()
  def element(tag, attrs \\ [], children \\ [], meta \\ %{}) when is_binary(tag),
    do: %__MODULE__{kind: :element, tag: tag, attrs: attrs, children: children, meta: meta}

  @doc "Builds a `:branch` node for the chosen branch `key`."
  @spec branch(term(), [child()], map()) :: t()
  def branch(key, children, meta \\ %{}),
    do: %__MODULE__{kind: :branch, key: key, children: children, meta: meta}

  @doc "Builds a `:keyed` node from `:fragment` items."
  @spec keyed([child()], map()) :: t()
  def keyed(items, meta \\ %{}), do: %__MODULE__{kind: :keyed, children: items, meta: meta}

  @doc "Builds a `:fragment` node, optionally keyed for item identity."
  @spec fragment([child()], term(), map()) :: t()
  def fragment(children, key \\ nil, meta \\ %{}),
    do: %__MODULE__{kind: :fragment, key: key, children: children, meta: meta}

  @doc "Builds a `:component` node."
  @spec component(StarView.Template.t(), map()) :: t()
  def component(value, meta \\ %{}), do: %__MODULE__{kind: :component, value: value, meta: meta}
end
