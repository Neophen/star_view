defmodule StarView.Template do
  @moduledoc """
  StarView's own template representation, rendering to HTML and diffing into
  element patches. Compiled templates hold a `StarView.Template.Program` with
  evaluated values. Hand-built templates hold `StarView.Template.Node` trees.

  A snapshot holds already-evaluated values. Building one runs every chosen
  expression exactly once. Compiled rendering merges static markup; `diff/2`
  materializes both trees and can cost more than rendering a bounded region.
  It saves bytes on the wire, not database reads or expression evaluation.

  ## Rendering

  Compiled templates have `nodes: nil`; use `nodes/1` to inspect their tree.
  A template must hold either nodes or a compiled program, never both.

  `to_html/1` and `to_iodata/1` render server-side HTML. Static text and static
  attribute values are trusted compiler output and emitted verbatim. Dynamic
  values and attributes are escaped through the public `Phoenix.HTML` API with
  HEEx escaping rules, so rendering dynamic content needs `:phoenix_html`.
  Templates implement `Phoenix.HTML.Safe` for serialization by the Phoenix
  host. The native template tree rejects legacy HEEx values; components and
  slots used inside `~STAR` must also return `StarView.Template`.

  ## Diffing

  `diff/2` compares a previous snapshot with the next one and returns either
  `{:ok, patches}` or `{:reset, reason}`. Send each `StarView.Template.Patch`
  with `StarView.Elements.patch/3`; on reset, send the whole region again.

  Patches target existing elements by their DOM `id`. An element is a target
  only when:

    * its id is the element's only id attribute, matches
      `[A-Za-z][A-Za-z0-9_-]*` and is unchanged;
    * that id appears exactly once in both snapshots;
    * its tag, voidness and namespace are unchanged;
    * every ancestor has the same structure, branch keys and keyed order.

  Any other change bubbles up to the nearest target ancestor. A patched
  element replaces all of its descendants' patches, so patches never overlap.

  Reset reasons:

    * `:initial` - there is no baseline.
    * `:template_changed` - the template fingerprint changed.
    * `{:unaddressable, reason}` - a change has no target ancestor.
    * `{:duplicate_key, key}` and `:missing_key` - a keyed collection has
      ambiguous item identity.

  ## Limitations

    * Legacy HEEx values are incompatible. Inline `~H` sigils fail during
      compilation; legacy component/slot results fail with a conversion error
      during evaluation. Convert the page and its called components together.
    * Trusted raw HTML remains opaque; ids inside it cannot be checked for
      duplicates against the template. Keep document-wide ids unique.
    * Descendants of `svg` and `math`, `template`, `head`, raw-text elements,
      custom elements (such as Rocket hosts), elements marked `data-ignore*`
      and nodes with `meta[:browser_owned?]` are never targets. Changes there
      patch the nearest ancestor, which keeps the existing server-markup
      behavior rather than integrating with browser-owned lifecycles.
    * Patches always use the `:outer` mode and the `:html` namespace.
    * Targeting assumes the rendered HTML nests validly, so the browser keeps
      every element where the template put it.
  """

  alias StarView.Template.Diff
  alias StarView.Template.Node
  alias StarView.Template.Patch
  alias StarView.Template.Program
  alias StarView.Template.Renderer

  @type t :: %__MODULE__{
          fingerprint: binary() | nil,
          nodes: [Node.t() | Program.t()] | nil,
          program: Program.t() | nil,
          source: map()
        }

  @type reset_reason ::
          :initial
          | :template_changed
          | :missing_key
          | {:duplicate_key, term()}
          | {:unaddressable, atom()}

  defstruct fingerprint: nil, nodes: [], program: nil, source: %{}

  @doc "Renders the template to HTML iodata."
  @spec to_iodata(t()) :: iodata()
  def to_iodata(%__MODULE__{} = template), do: Renderer.to_iodata(template)

  @doc "Renders the template to an HTML binary."
  @spec to_html(t()) :: String.t()
  def to_html(%__MODULE__{} = template), do: template |> to_iodata() |> IO.iodata_to_binary()

  @doc """
  Returns the template as a fully expanded `StarView.Template.Node` list.

  Compiled templates hold a `StarView.Template.Program` and `nodes: nil`; this
  builds their tree from already-evaluated values without running template
  expressions again. Nested native templates under `:value` and `:component`
  nodes, including lists of them, are expanded too.
  """
  @spec nodes(t()) :: [Node.t()]
  def nodes(%__MODULE__{} = template), do: Program.template(template).nodes

  @doc false
  def representation!(%__MODULE__{nodes: nil, program: nil}),
    do: raise(ArgumentError, "a StarView.Template needs either nodes or a compiled program")

  def representation!(%__MODULE__{nodes: nodes, program: nil}), do: {:nodes, nodes}
  def representation!(%__MODULE__{nodes: nil, program: program}), do: {:program, program}

  def representation!(%__MODULE__{}),
    do:
      raise(
        ArgumentError,
        "ambiguous StarView.Template: set either nodes or a compiled program, not both"
      )

  @doc """
  Diffs the `previous` snapshot against `next`.

  Returns `{:ok, patches}` (empty when the HTML is unchanged) or
  `{:reset, reason}` when `next` must be sent whole. A `nil` baseline returns
  `{:reset, :initial}`.
  """
  @spec diff(t() | nil, t()) :: {:ok, [Patch.t()]} | {:reset, reset_reason()}
  def diff(previous, next), do: Diff.diff(previous, next)
end
