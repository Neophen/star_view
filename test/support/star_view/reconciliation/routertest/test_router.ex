defmodule StarView.RouterTest.TestRouter do
  use Phoenix.Router

  import StarView.Router

  star_view("/counter", StarView.RouterTest.CounterPage, event_methods: [:post, :delete])
  star_view_components("/ds")
end
