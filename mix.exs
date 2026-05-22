defmodule Mob.Cellular.MixProject do
  use Mix.Project

  @github_url "https://github.com/dl-alexandre/mob_cellular"
  @version "0.1.0"
  @description "Cellular fallback transport plugin for mob using push notification envelopes."

  def project do
    [
      app: :mob_cellular,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
          "CHANGELOG.md",
          "LICENSE"
        ]
      ]
    ]
  end

  def application do
    [
      mod: {MobCellular.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
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
        docs
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE
      )
    ]
  end
end
