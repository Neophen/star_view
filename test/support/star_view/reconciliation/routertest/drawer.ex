defmodule StarView.RouterTest.Drawer do
  use StarView.Component

  def handle_event("ping", _signals, conn) do
    patch_signals(conn, %{pong: true})
  end
end
