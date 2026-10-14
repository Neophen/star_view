defmodule StarView.RouterTest.ScopedRouter do
  use Phoenix.Router

  import StarView.Router

  # Relative module aliases follow Phoenix's scope expansion; the dispatcher
  # plug itself must remain exempt from that alias prefix.
  scope "/app", StarView do
    star_view("/counter", RouterTest.CounterPage)
    star_view_components("/ds")
  end
end
