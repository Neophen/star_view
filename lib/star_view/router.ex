defmodule StarView.Router do
  # Page/component/routing concepts adapted from dstar (MIT), Rico Trevisan, 2025.
  @moduledoc """
  Explicit Phoenix routes for optional StarView pages and components.

      import StarView.Router
      scope "/", MyAppWeb do
        star_view "/counter", CounterPage
        star_view_components "/ds"
      end

  Events default to POST, preserving the existing controller dispatch boundary.
  Select additional CSRF-protected methods with `:event_methods`. Page GET events
  require `get_events: true`; component GET events require an explicit module
  list, such as `get_events: [ReadOnlyComponent]`. GET handlers must be read-only,
  and mutation handlers must still guard their intended method.
  Options and method/read-module lists must be literal keyword/list values;
  module attributes, variables and sigils are not evaluated as options.
  """

  @unsafe_methods [:post, :put, :patch, :delete]

  @doc """
  Routes GET rendering, POST streaming, and POST `/_event/:event` by default.

  Options: `event_methods: [:post, :put, :patch, :delete]` selects unsafe event
  methods; `get_events: true` explicitly allows read-only GET events for this
  page. Aliased scopes expand the page module using Phoenix's normal semantics.
  """
  defmacro star_view(path, page, opts \\ []) do
    opts = literal_options!(opts)
    methods = event_methods!(opts)
    read? = page_read_events!(Keyword.get(opts, :get_events, false))

    quote bind_quoted: [path: path, page: page, methods: methods, read?: read?] do
      page = Phoenix.Router.scoped_alias(__MODULE__, page)
      get(path, StarView.Page.Plug, {:page, page}, alias: false)
      post(path, StarView.Page.Plug, {:stream, page}, alias: false)

      for method <- methods do
        match(method, StarView.Router.__event_path__(path), StarView.Page.Plug, {:event, page},
          alias: false
        )
      end

      if read? do
        get(StarView.Router.__event_path__(path), StarView.Page.Plug, {:event, page},
          alias: false
        )
      end
    end
  end

  @doc """
  Routes marked component/controller events under `base`, defaulting to POST.

  Additional unsafe methods use `:event_methods`. Read-only GET requires
  `get_events: [Module, ...]`: only those marked modules are dispatchable on the
  GET route. The list follows Phoenix scope aliases. A broad boolean GET opt-in
  is rejected so existing marked controllers retain their POST boundary.
  """
  defmacro star_view_components(base \\ "/ds", opts \\ []) do
    opts = literal_options!(opts)
    methods = event_methods!(opts)
    read_modules = component_read_events!(Keyword.get(opts, :get_events, []), __CALLER__)

    quote bind_quoted: [base: base, methods: methods, read_modules: read_modules] do
      for method <- methods do
        match(method, StarView.Router.__dispatch_path__(base), StarView.Dispatch, [],
          alias: false
        )
      end

      if read_modules != [] do
        modules = StarView.Router.__scoped_modules__(__MODULE__, read_modules)

        get(StarView.Router.__dispatch_path__(base), StarView.Dispatch, [only: modules],
          alias: false
        )
      end
    end
  end

  defp event_methods!(opts) do
    methods = Keyword.get(opts, :event_methods, [:post])

    if valid_methods?(methods),
      do: Enum.uniq(methods),
      else:
        raise(
          ArgumentError,
          ":event_methods must be a literal list of post, put, patch or delete"
        )
  end

  defp literal_options!(opts) do
    if keyword_options?(opts),
      do: opts,
      else: raise(ArgumentError, "StarView router options must be a literal keyword list")
  end

  defp keyword_options?(opts) when is_list(opts), do: Keyword.keyword?(opts)
  defp keyword_options?(_opts), do: false

  defp valid_methods?(methods) when is_list(methods),
    do: Enum.all?(methods, &(&1 in @unsafe_methods))

  defp valid_methods?(_methods), do: false

  defp page_read_events!(value) when is_boolean(value), do: value

  defp page_read_events!(_value),
    do: raise(ArgumentError, "page :get_events must be a literal boolean")

  defp component_read_events!(modules, env) when is_list(modules) do
    modules = Enum.map(modules, &Macro.expand(&1, env))

    if module_list?(modules),
      do: modules,
      else: raise(ArgumentError, "component :get_events must be a module list")
  end

  defp component_read_events!(_modules, _env),
    do: raise(ArgumentError, "component :get_events must be an explicit module list")

  defp module_list?(modules), do: Enum.all?(modules, &is_atom/1)

  if Code.ensure_loaded?(Phoenix.Router) do
    @doc false
    def __scoped_modules__(router, modules),
      do: Enum.map(modules, &Phoenix.Router.scoped_alias(router, &1))
  else
    @doc false
    def __scoped_modules__(_router, _modules),
      do: raise(ArgumentError, "StarView routing requires the optional Phoenix dependency")
  end

  @doc false
  def __event_path__(path), do: String.trim_trailing(path, "/") <> "/_event/:event"

  @doc false
  def __dispatch_path__(base), do: String.trim_trailing(base, "/") <> "/:module/:event"
end
