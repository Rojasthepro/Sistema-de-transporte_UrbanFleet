defmodule UrbanFleet.MixProject do
  use Mix.Project

  def project do
    [
      app: :urban_fleet,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Asegúrate de que esta línea esté correcta
  def application do
    [
      main_module: UrbanFleet.CLI, # <-- Añade esto para correrlo fácil
      mod: {UrbanFleet.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # No se necesitan dependencias externas para este proyecto
    ]
  end
end