defmodule StarView.AllowlistedTransportHandler do
  @moduledoc false

  def handle_event(conn, event, signals),
    do: StarView.TransportHandler.handle_event(event, signals, conn)
end
