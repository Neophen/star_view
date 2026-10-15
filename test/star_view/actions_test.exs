defmodule StarView.ActionsTest do
  use ExUnit.Case, async: true

  alias StarView.Actions
  alias StarView.TestHandlers.PageController

  test "encodes and decodes module names" do
    encoded = Actions.encode_module(PageController)

    assert encoded == "star_view-test_handlers-page_controller"
    assert Actions.decode_module(encoded) == {:ok, PageController}
  end

  test "generates module action expressions" do
    assert Actions.post(PageController, "increment") ==
             ~S|@post("/ds/star_view-test_handlers-page_controller/increment")|

    assert Actions.get(PageController, "show", prefix: "/admin") ==
             ~S|@get("/admin/ds/star_view-test_handlers-page_controller/show")|
  end

  test "generates dynamic action expressions" do
    action = Actions.post("increment")
    assert action =~ "encodeURIComponent(segment)"
    assert action =~ "})($_star_view_module)"
    assert action =~ ~s(+ "/increment")
  end

  test "every controller action preserves fetch options" do
    for verb <- [:get, :post, :put, :patch, :delete] do
      action =
        apply(Actions, verb, [
          PageController,
          "save",
          [opts: "{retry: 'never', retryMaxCount: 0}"]
        ])

      assert action ==
               "@#{verb}(\"/ds/star_view-test_handlers-page_controller/save\", {retry: 'never', retryMaxCount: 0})"
    end
  end

  test "dynamic actions preserve fetch options and URL encoding together" do
    action =
      Actions.post("save/name", prefix: "/admin", opts: "{requestCancellation: controller}")

    assert action =~ ~s("/admin/ds/")
    assert action =~ "encodeURIComponent(segment)"
    assert action =~ ~s(+ "/save%2Fname", {requestCancellation: controller})

    assert Actions.post("save", module: "literal/name", opts: "{payload: {csrf: $csrf}}") ==
             ~S|@post("/ds/literal%2Fname/save", {payload: {csrf: $csrf}})|
  end

  test "fetch options reject values that are not trusted JavaScript text" do
    assert_raise ArgumentError, ":opts must be trusted JavaScript text", fn ->
      Actions.post(PageController, "save", opts: %{})
    end

    assert_raise ArgumentError, ":opts must be trusted JavaScript text", fn ->
      Actions.post("save", opts: [])
    end
  end

  test "encodes special event values as one literal route segment" do
    event = "save/'\\?%#\nč."
    action = Actions.post(PageController, event)

    assert action ==
             ~S|@post("/ds/star_view-test_handlers-page_controller/save%2F%27%5C%3F%25%23%0A%C4%8D%2E")|

    refute action =~ "\n"
  end

  test "literal module overrides remain data rather than executable syntax" do
    assert Actions.post("save", module: "x'); evil();//") ==
             ~S|@post("/ds/x%27%29%3B%20evil%28%29%3B%2F%2F/save")|
  end

  test "custom signal module overrides fail loudly and the default signal stays compatible" do
    assert_raise ArgumentError, fn -> Actions.post("save", module: "$signal") end
    assert Actions.post("save", module: "$_star_view_module") == Actions.post("save")
  end

  test "serializes prefixes as JavaScript strings" do
    assert Actions.post(PageController, "save", prefix: ~s(/it's "safe")) ==
             ~S|@post("/it's \"safe\"/ds/star_view-test_handlers-page_controller/save")|
  end

  test "rejects prefixes that change origin or URL structure" do
    prefixes = [
      "https://evil.test",
      "//evil.test",
      "/../evil",
      "/%2e%2e/evil",
      "/x?y",
      "/x#y",
      "/x\\y",
      "/%5cx",
      "/x\n",
      "/x%0a",
      "/%",
      "/%FF",
      <<47, 255>>
    ]

    Enum.each(prefixes, &assert_invalid_prefix/1)
  end

  test "normalizes safe relative prefixes for compatibility" do
    assert Actions.post(PageController, "save", prefix: "admin/") ==
             ~S|@post("/admin/ds/star_view-test_handlers-page_controller/save")|
  end

  test "escapes JavaScript line separator characters in prefixes" do
    action = Actions.post(PageController, "save", prefix: "/x\u2028\u2029")
    assert action =~ "\\u2028\\u2029"
    refute action =~ "\u2028"
  end

  test "rejects empty and exact dot segments" do
    Enum.each(["", ".", "..", <<255>>], &assert_invalid_event/1)
    assert_raise ArgumentError, fn -> Actions.post("save", module: "..") end
  end

  defp assert_invalid_prefix(prefix) do
    assert_raise ArgumentError, fn -> Actions.post(PageController, "save", prefix: prefix) end
  end

  defp assert_invalid_event(event) do
    assert_raise ArgumentError, fn -> Actions.post(PageController, event) end
  end
end
