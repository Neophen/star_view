defmodule StarView.Page.PlugTest.RootLayoutPage do
  use StarView.Page

  @impl StarView.Page
  def mount(conn, _params) do
    Phoenix.Controller.put_root_layout(conn,
      html: {StarView.Page.PlugTest.TestLayouts, :root}
    )
  end

  @impl StarView.Page
  def render(assigns), do: ~H'<div id="opted-in">content</div>'
end
