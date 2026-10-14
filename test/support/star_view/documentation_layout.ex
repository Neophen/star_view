defmodule StarView.DocumentationLayout do
  @moduledoc false

  use Phoenix.Component

  attr(:conn, :map, required: true)
  slot(:inner_block, required: true)

  def app(assigns) do
    ~H"""
    <main data-signals={StarView.Controller.init_signals(@conn)}>
      {render_slot(@inner_block)}
    </main>
    """
  end
end
