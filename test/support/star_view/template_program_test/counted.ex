defmodule StarView.TemplateProgramTest.Counted do
  @moduledoc false
  use Phoenix.Component

  import StarView.Template.Sigils

  def page(assigns) do
    ~STAR"""
    <main id="main">
      <p id="text" title={note(:title)}>{note(:text)}</p>
      <ul id="list">
        <li :for={item <- note(:items)} :key={item} id={"item-#{item}"}>{item}</li>
      </ul>
    </main>
    """
  end

  defp note(:items), do: tap([1, 2], fn _ -> send(self(), {:evaluated, :items}) end)
  defp note(label), do: tap("value", fn _ -> send(self(), {:evaluated, label}) end)
end
