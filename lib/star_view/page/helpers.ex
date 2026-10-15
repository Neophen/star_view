defmodule StarView.Page.Helpers do
  @moduledoc """
  Template and handler helpers imported by `use StarView.Page`.

  - `event/1,2` — Datastar action expression targeting the page's own
    `_event` route, resolved client-side via `location.pathname`.
  - `connect/0,1` — Datastar action expression opening the page's SSE stream.
  - `patch/3,4` — render a function component into a `patch_elements` call.
  """

  @verbs ~w(get post put patch delete)a
  @retry_modes ~w(auto always error never)a

  @doc """
  Builds a page-local Datastar action expression.

      event("increment")
      # Validated local pathname + encoded /_event/increment segment

      event("remove", verb: :delete)
      # Requires event_methods: [:post, :delete] on the page route

  The URL is computed in the browser, so path params (workspace slugs,
  ids) need no server-side threading. Event names become a single URL path segment and are
  percent-encoded as literal data. Empty names and exact dot segments raise.

  Trailing slashes in the path are stripped client-side so pages mounted
  at "/" or visited with a trailing slash don't produce protocol-relative
  ("//") or double-slash URLs.

  ## Options

  - `:verb` — `:get | :post | :put | :patch | :delete` (default `:post`)
  - `:opts` — raw JS object string appended as the action's options,
    e.g. `"{retryMaxCount: 5}"`. Trusted developer input only — it is
    emitted verbatim into the expression.

  > #### GET events are not CSRF-protected {: .warning}
  >
  > `Plug.CSRFProtection` does not check tokens on GET requests, so
  > `verb: :get` events can be triggered cross-site. Use `:get` only for
  > side-effect-free reads.
  """
  def event(name, opts \\ []) when is_binary(name) and is_list(opts) do
    verb = action_verb!(opts)

    path =
      StarView.Actions.javascript_string("/_event/" <> StarView.Actions.encode_segment!(name))

    args = StarView.Actions.browser_local_path("location.pathname") <> " + " <> path
    action(verb, args, Keyword.get(opts, :opts))
  end

  @doc false
  def action_verb!(opts) do
    case Keyword.get(opts, :verb, :post) do
      verb when verb in @verbs ->
        verb

      verb ->
        raise ArgumentError, "invalid verb: #{inspect(verb)}; expected one of #{inspect(@verbs)}"
    end
  end

  @doc false
  defdelegate action(verb, args, extra), to: StarView.Actions, as: :expression

  @doc """
  Builds the stream-connect expression for `data-init` /
  `data-on:online__window`.

      connect()
      # POST to the validated current pathname, using the client's default retry policy

      connect(retry: :always)
      # Reconnect after successful read-stream closures too

      connect(include_search: true)
      # Include the current query string

  ## Options

  - `:opts` — override the options object (default `"{retryMaxCount: Infinity}"`)
  - `:retry` — `:auto | :always | :error | :never`. Opting into a retry mode
    uses a default maximum of 64 consecutive failures (`:never` uses zero)
    unless `:opts` sets a different maximum. The typed mode overrides `retry`
    in a custom object expression.
  - `:include_search` — append `location.search` so query params reach
    `handle_connect` (pages whose render depends on them, e.g. `?step=`).

  Always emits `@post` — StarView streams connect over POST.
  `:always` reconnects even after a deliberate server halt. Use it for live
  resources that reconcile an authorized snapshot on every connection, not
  mutation requests. The default remains unchanged for existing pages.
  """
  def connect(opts \\ []) when is_list(opts) do
    extra = connect_options(opts)

    base = StarView.Actions.browser_local_path("location.pathname", false)

    url =
      if Keyword.get(opts, :include_search, false) do
        base <> " + location.search"
      else
        base
      end

    action(:post, url, extra)
  end

  defp connect_options(opts) do
    retry = Keyword.fetch(opts, :retry)
    connect_retry(retry, Keyword.get(opts, :opts, default_connect_options(retry)))
  end

  # Keyword.fetch/2 returns :error when the caller did not select a retry mode.
  defp default_connect_options(:error), do: "{retryMaxCount: Infinity}"
  defp default_connect_options({:ok, :never}), do: "{retryMaxCount: 0}"
  defp default_connect_options(_retry), do: "{retryMaxCount: 64}"

  defp connect_retry(:error, extra), do: extra

  defp connect_retry({:ok, retry}, extra) when retry in @retry_modes and is_binary(extra),
    do: "{...(#{extra}), retry: #{StarView.Actions.javascript_string(Atom.to_string(retry))}}"

  defp connect_retry({:ok, retry}, _extra) when retry not in @retry_modes,
    do:
      raise(
        ArgumentError,
        ":retry must be one of #{inspect(@retry_modes)}, got: #{inspect(retry)}"
      )

  defp connect_retry(_retry, _extra),
    do: raise(ArgumentError, ":opts must be trusted JavaScript text")

  @doc """
  Renders a function component and pipes it to `StarView.Elements.patch/3`.

      conn |> patch(&history/1, value: count)
      conn |> patch(&item_card/1, [item: item], selector: "#row-1", mode: :outer)

  With no `:selector`, Datastar matches elements by their `id` attribute,
  so the component's root element must carry one.
  """
  def patch(conn, component, assigns, opts \\ [])
      when is_function(component, 1) and (is_list(assigns) or is_map(assigns)) do
    # Direct function-component calls bypass the HEEx engine, which is what
    # normally adds :__changed__; without it, any assign/3 inside raises.
    assigns = assigns |> Map.new() |> Map.put_new(:__changed__, nil)
    html = component.(assigns)
    StarView.Elements.patch(conn, html, opts)
  end

  @doc false
  def validate_event_name!(name) do
    StarView.Actions.encode_segment!(name)
    :ok
  end
end
