defmodule StarView.TransportAdapter do
  @moduledoc false

  def send_chunked({:start_error, reason}, _status, _headers), do: raise(reason)
  def send_chunked(state, _status, _headers), do: {:ok, "", state}

  def chunk({:error, reason}, _data), do: {:error, reason}

  def chunk({:notify, pid}, data) do
    send(pid, {:chunk, IO.iodata_to_binary(data)})
    :ok
  end
end
