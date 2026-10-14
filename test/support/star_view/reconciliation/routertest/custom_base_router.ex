defmodule StarView.RouterTest.CustomBaseRouter do
  use Phoenix.Router

  import StarView.Router

  star_view_components("/actions")
end
