defmodule UrbanFleet.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # El Registry es clave. Lo usaremos para dos cosas:
    # 1. PubSub: Notificar a conductores (key: :drivers_online)
    # 2. Lookup: Encontrar el PID de un viaje por su ID (key: "trip_#{id}")
    registry_spec = {Registry, keys: :duplicate, name: Registry.UrbanFleet}

    children = [
      # 1. El Registry
      registry_spec,
      # 2. El Agente de Ubicaciones
      {UrbanFleet.Location, []},
      # 3. El GenServer de Usuarios (maneja users.dat)
      {UrbanFleet.UserManager, []},
      # 4. El GenServer de Estadísticas de Conductores (bonos por viajes consecutivos)
      {UrbanFleet.DriverStats, []},
      # 5. El GenServer de Logs (maneja results.log)
      {UrbanFleet.TripLogger, []},
      # 6. El Supervisor Dinámico (vigila los procesos 'Trip')
      {UrbanFleet.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: UrbanFleet.ApplicationSupervisor]
    Supervisor.start_link(children, opts)
  end
end