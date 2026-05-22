defmodule Mob.Cellular.MixProject do
  use Mix.Project

  @github_url "https://github.com/dl-alexandre/mob_cellular"
  @version "0.2.0"
  @description "Cellular fallback transport plugin for mob using push notification envelopes."

  def project do
    [
      app: :mob_cellular,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: @description,
      package: package(),
      source_url: @github_url,
      homepage_url: @github_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "docs/CARRIER_DECISION.md",
          "docs/COST_AND_BATTERY.md",
          "docs/HARDWARE_VALIDATION.md",
          "CHANGELOG.md",
          "LICENSE"
        ]
      ]
    ]
  end

  def application do
    [
      mod: {MobCellular.Application, []},
      extra_applications: [:logger, :telemetry]
    ]
  end

  def cli do
    [
      preferred_envs: [check: :test]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 1.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.2", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Changelog" => "#{@github_url}/blob/main/CHANGELOG.md",
        "mob" => "https://github.com/GenericJam/mob",
        "mob_dev" => "https://github.com/GenericJam/mob_dev"
      },
      files: ~w(
        lib
        priv/mob_plugin.exs
        scripts
        docs
        mix.exs
        README.md
        CONTRIBUTING.md
        CHANGELOG.md
        LICENSE
      )
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "test",
        "credo --strict"
      ]
    ]
  end
end
