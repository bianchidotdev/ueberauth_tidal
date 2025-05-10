defmodule UeberauthTidal.Mixfile do
  use Mix.Project

  def project do
    [
      app: :ueberauth_tidal,
      version: "0.1.0",
      name: "Ueberauth Tidal Strategy",
      package: package(),
      elixir: "~> 1.8",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/bianchidotdev/ueberauth_tidal",
      homepage_url: "https://github.com/bianchidotdev/ueberauth_tidal",
      description: description(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [applications: [:logger, :oauth2, :ueberauth]]
  end

  defp deps do
    [
      {:ueberauth, "~> 0.7"},
      {:oauth2, "~> 1.0 or ~> 2.0"},
      {:jason, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp docs do
    [extras: docs_extras(), main: "extra-readme"]
  end

  defp docs_extras do
    ["README.md"]
  end

  defp description do
    "An Uberauth strategy for Tidal authentication."
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE", ".gitignore"],
      maintainers: ["bianchidotdev"],
      licenses: ["MIT"],
      links: %{GitHub: "https://github.com/bianchidotdev/ueberauth_tidal"}
    ]
  end
end
