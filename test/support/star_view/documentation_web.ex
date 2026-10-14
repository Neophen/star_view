defmodule StarView.DocumentationWeb do
  @moduledoc false

  defmacro __using__(:star_view) do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      use StarView
      use Phoenix.Component

      import Phoenix.Component, except: [assign: 3]
      import Plug.Conn

      alias StarView.DocumentationLayout, as: Layout

      plug(:put_root_layout, false)
    end
  end

  defmacro __using__(:controller) do
    quote do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
    end
  end
end
