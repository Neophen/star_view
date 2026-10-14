defmodule StarView.Page.PlugTest.TestLayouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <html>
      <body id="root-layout">{@inner_content}</body>
    </html>
    """
  end
end
