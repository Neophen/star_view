defmodule StarView.TemplateTest.Legacy do
  @moduledoc false
  use Phoenix.Component

  attr(:title, :string, required: true)
  def badge(assigns), do: ~H'<span class="badge">{@title}</span>'

  def escaped(assigns) do
    ~H"""
    <section id="content" title="A &amp; B">
      <input disabled={@disabled} class={["one", @class]} {@rest} />
      <p title={@value}>{@value}</p>
    </section>
    """
  end
end
