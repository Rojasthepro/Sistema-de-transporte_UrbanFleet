defmodule UrbanFleetWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # --- INICIO DE TU LÓGICA PEGADA ---
      # Inicia el Registry para PubSub y 'lookup' de viajes
      {Registry, keys: :duplicate, name: Registry.UrbanFleet},

      # Inicia los GenServers y Agentes de tu proyecto
      {UrbanFleet.Location, []},
      {UrbanFleet.UserManager, []},
      {UrbanFleet.DriverStats, []},
      {UrbanFleet.TripLogger, []},
      {UrbanFleet.UserManagerJSON, []},
      {UrbanFleet.TripLock, []},  # Bloqueo para prevenir creación simultánea de viajes

      # Inicia el DynamicSupervisor para los viajes
      {UrbanFleet.Supervisor, []},
      # --- FIN DE TU LÓGICA PEGADA ---

      # Hijos propios de Phoenix (los que ya tenías)
      UrbanFleetWebWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:urban_fleet_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: UrbanFleetWeb.PubSub},
      # Start to serve requests, typically the last entry
      UrbanFleetWebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: UrbanFleetWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UrbanFleetWebWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end