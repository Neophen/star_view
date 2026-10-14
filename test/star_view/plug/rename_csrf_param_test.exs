defmodule StarView.Plug.RenameCsrfParamTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias StarView.Plug.RenameCsrfParam

  defp call(conn, opts \\ []) do
    RenameCsrfParam.call(conn, RenameCsrfParam.init(opts))
  end

  test "copies csrf param into body_params _csrf_token" do
    conn =
      conn(:post, "/")
      |> Map.put(:params, %{"csrf" => "secret-token"})
      |> Map.put(:body_params, %{"other" => "value"})

    conn = call(conn)

    assert conn.body_params == %{"other" => "value", "_csrf_token" => "secret-token"}
  end

  test "query _csrf_token cannot suppress a signal token" do
    conn =
      conn(:post, "/")
      |> Map.put(:params, %{"csrf" => "ignored", "_csrf_token" => "existing"})
      |> Map.put(:body_params, %{})

    conn = call(conn)

    assert conn.body_params == %{"_csrf_token" => "ignored"}
  end

  test "leaves conn unchanged when csrf param is absent" do
    conn =
      conn(:post, "/")
      |> Map.put(:params, %{"other" => "value"})
      |> Map.put(:body_params, %{"field" => "x"})

    conn = call(conn)

    assert conn.body_params == %{"field" => "x"}
  end

  test "supports a custom :from param name" do
    conn =
      conn(:post, "/")
      |> Map.put(:params, %{"my_csrf" => "custom-token"})
      |> Map.put(:body_params, %{})

    conn = call(conn, from: "my_csrf")

    assert conn.body_params == %{"_csrf_token" => "custom-token"}
  end

  test "existing body _csrf_token takes precedence" do
    conn = conn(:post, "/", %{"_csrf_token" => "form", "csrf" => "signal"})
    assert call(conn).body_params["_csrf_token"] == "form"
  end

  test "DELETE gets the token from Datastar query JSON" do
    query = URI.encode_query(%{"datastar" => ~s({"csrf":"delete-token"})})
    conn = call(conn(:delete, "/?#{query}"))
    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert Plug.Conn.get_req_header(conn, "x-csrf-token") == ["delete-token"]
  end

  test "body signal takes precedence over merged query params" do
    conn = conn(:post, "/?csrf=query&_csrf_token=query", %{"csrf" => "body"})
    assert call(conn).body_params["_csrf_token"] == "body"
  end

  test "custom datastar query key and source are supported" do
    query = URI.encode_query(%{"ds" => ~s({"my_csrf":"custom"})})
    result = call(conn(:delete, "/?#{query}"), from: "my_csrf", datastar_param: "ds")
    assert Plug.Conn.get_req_header(result, "x-csrf-token") == ["custom"]
  end

  test "a raw POST query token passes CSRF protection without hiding body signals" do
    {token, state} = csrf_credentials()
    query = URI.encode_query(%{"csrf" => token})

    conn =
      conn(:post, "/?#{query}", ~s({"count":3}))
      |> Map.put(:secret_key_base, String.duplicate("s", 64))
      |> init_test_session(%{"_csrf_token" => state})
      |> call()
      |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))

    assert conn.body_params == %Plug.Conn.Unfetched{aspect: :body_params}
    assert {:ok, %{"count" => 3}, conn} = StarView.Signals.fetch(conn)
    assert {:ok, "", _conn} = Plug.Conn.read_body(conn)
  end

  test "an explicit valid CSRF header wins over a forged raw-body query token" do
    {token, state} = csrf_credentials()

    conn =
      conn(:post, "/?csrf=forged", ~s({"count":5}))
      |> Map.put(:secret_key_base, String.duplicate("s", 64))
      |> init_test_session(%{"_csrf_token" => state})
      |> Plug.Conn.put_req_header("x-csrf-token", token)
      |> call()
      |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))

    assert Plug.Conn.get_req_header(conn, "x-csrf-token") == [token]
    assert {:ok, %{"count" => 5}, _conn} = StarView.Signals.fetch(conn)
  end

  test "non-string query tokens preserve the raw body without creating an invalid header" do
    query = URI.encode_query(%{"datastar" => ~s({"csrf":123})})
    conn = call(conn(:post, "/?#{query}", ~s({"count":3})))
    assert Plug.Conn.get_req_header(conn, "x-csrf-token") == []
    assert {:ok, %{"count" => 3}, _conn} = StarView.Signals.fetch(conn)
  end

  defp csrf_credentials() do
    token = Plug.CSRFProtection.get_csrf_token()
    {token, Plug.CSRFProtection.dump_state()}
  end

  test "malformed and non-object query documents do not create a token" do
    Enum.each(["{", "[1]", "null", ~s("scalar")], &assert_no_query_token/1)
  end

  defp assert_no_query_token(json) do
    query = URI.encode_query(%{"datastar" => json})
    result = call(conn(:delete, "/?#{query}"))
    refute Map.has_key?(result.body_params, "_csrf_token")
  end
end
