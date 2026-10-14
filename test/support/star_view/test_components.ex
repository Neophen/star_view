defmodule StarView.TestComponents do
  @moduledoc false

  use Phoenix.Component

  def tracked(assigns) do
    assigns = assign(assigns, :display, assigns.count + 1)

    ~H"""
    <div id="tracked">{@display}</div>
    """
  end
end
