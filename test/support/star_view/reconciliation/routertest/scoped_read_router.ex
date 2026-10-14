defmodule StarView.RouterTest.ScopedReadRouter do
  use Phoenix.Router

  import StarView.Router

  scope "/app", StarView do
    star_view "/reader", RouterTest.ReadPage, get_events: true
    star_view_components "/ds", get_events: [RouterTest.Drawer]
  end
end
