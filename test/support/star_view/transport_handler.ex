defmodule StarView.TransportHandler do
  @moduledoc false

  def __star_view_handler__(), do: true

  def handle_event("write", _signals, conn) do
    conn |> Plug.Conn.assign(:written, true) |> StarView.patch_signals(%{saved: true})
  end

  def handle_event("raise", _signals, _conn), do: raise("failed to send SSE event: :closed")

  def handle_event("body", signals, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    conn |> Plug.Conn.assign(:unread_body, body) |> Plug.Conn.assign(:signals, signals)
  end
end
