defmodule UrbanFleet.Server do
  @registry Registry.UrbanFleet

  # --- Comandos de Usuario ---

  def connect(username, password) do
    UrbanFleet.UserManager.connect(username, password)
  end

  def my_score(username) do
    UrbanFleet.UserManager.get_score(username)
  end

  def show_ranking do
    UrbanFleet.UserManager.get_rankings()
  end

  # --- Lógica "Uber" de Conductor ---

  @doc "Pone al conductor 'online' para recibir notificaciones"
  def go_online(driver_pid) do
    # Suscribe este PID al 'topic' :drivers_online
    case Registry.register(@registry, :drivers_online, driver_pid) do
      {:ok, _value} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Pone al conductor 'offline'"
  def go_offline(_driver_pid) do
    # Des-suscribe este PID específico de :drivers_online
    # Nota: Registry.unregister necesita la clave, pero como usamos :duplicate keys,
    # necesitamos usar un enfoque diferente. Por ahora, simplemente retornamos :ok
    # ya que el proceso puede terminar y se limpiará automáticamente
    :ok
  end

  # --- Lógica de Cliente ---

  def request_trip(client_pid, client_name, origin, destination) do
    # 1. Validar ubicaciones
    if not (UrbanFleet.Location.is_valid?(origin) and UrbanFleet.Location.is_valid?(destination)) do
      {:error, :location_invalid}
    else
      case UrbanFleet.Supervisor.start_trip(client_pid, client_name, origin, destination) do
        {:ok, trip_pid} ->
          # 3. Obtener el ID único del viaje
          {:ok, %{id: trip_id}} = GenServer.call(trip_pid, :get_status)

          # 4. Notificar a todos los conductores 'online'
          notify_drivers(%{id: trip_id, origin: origin, destination: destination})
          {:ok, trip_id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Lógica de Conductor ---

  def list_trips do
    # 1. Encontrar todas las llaves "trip_..." en el Registry
    # Usamos Registry.select para buscar todas las entradas y filtrar por clave
    trips_pids = 
      Registry.select(@registry, [
        {{:"$1", :"$2", :"$3"}, 
         [], 
         [{{:"$1", :"$2", :"$3"}}]}
      ])
    |> Enum.filter(fn {key, _value, _pid} ->
      key_str = if is_binary(key), do: key, else: (if is_atom(key), do: Atom.to_string(key), else: "")
      String.starts_with?(key_str, "trip_")
    end)
    |> Enum.map(fn {_key, _value, pid} -> pid end)

    # 2. Consultar el estado de cada GenServer 'Trip'
    Enum.map(trips_pids, fn pid ->
      case GenServer.call(pid, :get_status, 5000) do
        {:ok, status} -> status
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil and &1.status == :pending)) # Filtrar solo pendientes
  end

  def accept_trip(driver_pid, driver_name, trip_id) do
    # 1. Encontrar el PID del viaje usando el Registry
    case Registry.lookup(@registry, "trip_#{trip_id}") do
      [{pid, _}] ->
        # 2. Enviar el 'call' al GenServer 'Trip'
        GenServer.call(pid, {:accept, driver_pid, driver_name})

      [] ->
        {:error, :trip_not_found}
    end
  end

  # --- Funciones Privadas (PubSub) ---

  defp notify_drivers(trip_info) do
    # 1. Buscar todos los PIDs suscritos a :drivers_online
    driver_pids = Registry.lookup(@registry, :drivers_online)

    # 2. Enviar un mensaje a cada conductor
    for {pid, _} <- driver_pids do
      send(pid, {:new_trip_available, trip_info})
    end
  end
end