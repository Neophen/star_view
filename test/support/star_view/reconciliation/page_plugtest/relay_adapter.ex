defmodule StarView.Page.PlugTest.RelayAdapter do
  def read_req_body(%{inner: inner} = state, opts) do
    {status, body, inner} = Plug.Adapters.Test.Conn.read_req_body(inner, opts)
    {status, body, %{state | inner: inner}}
  end

  def chunk(%{inner: inner, pid: pid} = state, body) do
    send(pid, {:sse_chunk, IO.iodata_to_binary(body)})

    {:ok, sent, inner} = Plug.Adapters.Test.Conn.chunk(inner, body)
    {:ok, sent, %{state | inner: inner}}
  end

  def send_chunked(%{inner: inner} = state, status, headers) do
    {:ok, sent, inner} = Plug.Adapters.Test.Conn.send_chunked(inner, status, headers)
    {:ok, sent, %{state | inner: inner}}
  end
end
