defmodule StarView.RouterTest.ReadRouter do
  use Phoenix.Router

  import StarView.Router

  star_view "/reader", StarView.RouterTest.ReadPage, get_events: true
  star_view_components "/ds", get_events: [StarView.RouterTest.Drawer]
end
