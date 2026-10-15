defmodule StarView.Template.Patch do
  @moduledoc """
  One element patch produced by `StarView.Template.diff/2`.

  `selector` targets an element that exists in the previous render and
  `elements` is its new outer HTML. Send it with `StarView.Elements.patch/3`:

      StarView.Elements.patch(conn, patch.elements, StarView.Template.Patch.opts(patch))
  """

  @type t :: %__MODULE__{
          selector: String.t(),
          elements: String.t(),
          mode: :outer,
          namespace: :html | :svg | :mathml
        }

  defstruct selector: nil, elements: nil, mode: :outer, namespace: :html

  @doc "Returns `StarView.Elements.patch/3` options for the patch."
  @spec opts(t()) :: keyword()
  def opts(%__MODULE__{selector: selector, mode: mode, namespace: namespace}),
    do: [selector: selector, mode: mode, namespace: namespace]
end
