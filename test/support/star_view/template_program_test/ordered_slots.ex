defmodule StarView.TemplateProgramCompilerTest.OrderedSlots do
  @moduledoc false
  use Phoenix.Component

  import StarView.Template.Sigils

  def page(assigns) do
    ~STAR"""
    <.target value={note(:attribute)}>
      <:zeta value={note(:zeta)} />
      <:alpha value={note(:alpha)} />
    </.target>
    """
  end

  attr(:value, :any)

  slot :alpha do
    attr(:value, :any)
  end

  slot :zeta do
    attr(:value, :any)
  end

  defp target(assigns), do: ~STAR"<p>target</p>"

  defp note(label), do: tap(label, &send(self(), {:slot_value, &1}))
end
