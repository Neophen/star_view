defmodule StarView.MixProject do
  use Mix.Project

  @version "0.3.18"

  def project() do
    [
      app: :star_view,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir SDK for Datastar SSE events with Plug and Phoenix helpers.",
      package: package(),
      docs: docs(),
      source_url: "https://github.com/Neophen/star_view",
      homepage_url: "https://hexdocs.pm/star_view"
    ]
  end

  def application() do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps() do
    [
      {:quokka, "~> 2.12", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.14"},
      {:igniter, "~> 0.6", optional: true},
      {:phoenix, "~> 1.7", optional: true},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp package() do
    [
      name: "star_view",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/Neophen/star_view",
        "Datastar" => "https://data-star.dev"
      },
      files: ~w(assets lib priv guides mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs() do
    [
      main: "overview",
      api_reference: false,
      logo: "assets/logo.png",
      extra_section: "GUIDES",
      source_ref: "v#{@version}",
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: groups_for_modules(),
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp extras() do
    [
      "guides/introduction/overview.md",
      "guides/introduction/installation.md",
      "guides/phoenix/web_module.md",
      "guides/phoenix/layout.md",
      "guides/phoenix/auth.md",
      "guides/phoenix/development_server.md",
      "guides/core/patch_signals.md",
      "guides/core/patch_element.md",
      "guides/core/stream_deduplication.md",
      "guides/core/csrf.md",
      "guides/comparison/liveview_vs_star_view.md",
      "guides/reference/api_overview.md",
      "guides/reference/migration_from_dstar.md",
      {"CHANGELOG.md", title: "Changelog"}
    ]
  end

  defp groups_for_extras() do
    [
      Introduction: ~r/guides\/introduction\/.?/,
      Phoenix: ~r/guides\/phoenix\/.?/,
      "Core Concepts": ~r/guides\/core\/.?/,
      Comparison: ~r/guides\/comparison\/.?/,
      Reference: ~r/guides\/reference\/.?/,
      "Release Notes": ~r/CHANGELOG/
    ]
  end

  defp groups_for_modules() do
    [
      Core: [
        StarView,
        StarView.SSE,
        StarView.Elements,
        StarView.Signals,
        StarView.Scripts,
        StarView.Actions,
        StarView.JSON,
        StarView.StreamRegistry
      ],
      Plugs: [
        StarView.Plug.Dispatch,
        StarView.Plug.RenameCsrfParam
      ],
      Phoenix: [
        StarView.Controller,
        StarView.Dispatch
      ]
    ]
  end
end
