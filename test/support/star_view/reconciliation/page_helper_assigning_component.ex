defmodule StarView.Page.HelpersTest.AssigningComponent do
  use Phoenix.Component

  def banner(assigns) do
    assigns = assign(assigns, :label, "n=#{assigns.n}")

    ~H"""
    <div id="banner">{@label}</div>
    """
  end
end
