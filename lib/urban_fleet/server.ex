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
      # Normalizar el client_name para asegurar consistencia
      client_name_normalized = client_name |> String.trim()
      
      case UrbanFleet.Supervisor.start_trip(client_pid, client_name_normalized, origin, destination) do
        {:ok, trip_pid} ->
          # 3. Obtener el ID único del viaje
          case GenServer.call(trip_pid, :get_status, 5000) do
            {:ok, %{id: trip_id}} ->
              # 4. Notificar a todos los conductores 'online'
              notify_drivers(%{id: trip_id, origin: origin, destination: destination})
              {:ok, trip_id}
            _ ->
              {:error, :trip_creation_failed}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Lógica de Conductor ---

  @doc "Obtiene todos los viajes de un cliente específico (por username - más robusto que client_pid)"
  def list_client_trips(_client_pid, username) when is_binary(username) do
    # Normalizar el username ANTES de buscar viajes
    username_normalized = username |> String.trim() |> String.downcase()
    
    # Buscar todos los viajes en el Registry
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

    # Filtrar SOLO por username (más robusto que client_pid que cambia con cada sesión)
    # Procesar secuencialmente para evitar problemas de concurrencia
    Enum.reduce(trips_pids, [], fn pid, acc ->
      try do
        # Obtener el nombre del cliente del viaje
        case GenServer.call(pid, :get_client_name, 1000) do
          {:ok, trip_client_name} -> 
            # Normalizar también el nombre del viaje para comparación
            trip_client_name_normalized = trip_client_name |> String.trim() |> String.downcase()
            # Solo incluir si el username coincide EXACTAMENTE (case-insensitive)
            if trip_client_name_normalized == username_normalized do
              # Obtener el estado del viaje solo si el username coincide
              case GenServer.call(pid, :get_status, 1000) do
                {:ok, status} -> [status | acc]
                _ -> acc
              end
            else
              # El viaje no pertenece a este usuario, no incluirlo
              acc
            end
          _ -> acc
        end
      rescue
        _e -> acc
      catch
        :exit, {:timeout, _} -> acc
        :exit, {:normal, _} -> acc
        :exit, {:noproc, _} -> acc
        :exit, _ -> acc
        _, _ -> acc
      end
    end)
    |> Enum.reverse()
  end

  # Versión sin username (para compatibilidad, pero no recomendada)
  def list_client_trips(client_pid, nil) do
    # Si no se proporciona username, usar el método antiguo por client_pid
    # (menos seguro, pero mantiene compatibilidad)
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

    Enum.map(trips_pids, fn pid ->
      try do
        case GenServer.call(pid, :get_client_pid, 1000) do
          {:ok, trip_client_pid} when trip_client_pid == client_pid ->
            case GenServer.call(pid, :get_status, 1000) do
              {:ok, status} -> status
              _ -> nil
            end
          _ -> nil
        end
      rescue
        _e -> nil
      catch
        :exit, _ -> nil
        _, _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
  end

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

  @doc "Cancela un viaje (puede ser llamado por cliente o conductor)"
  def cancel_trip(canceler_name, trip_id, reason \\ "Sin razón especificada") do
    case Registry.lookup(@registry, "trip_#{trip_id}") do
      [{pid, _}] ->
        # El proceso puede terminar durante la cancelación, así que manejamos el caso
        try do
          result = GenServer.call(pid, {:cancel, canceler_name, reason}, 5000)
          # Si recibimos una respuesta, la cancelación fue exitosa
          case result do
            :ok -> :ok
            {:error, :unauthorized} -> {:error, :unauthorized}
            {:error, _} = error -> error
            _ -> :ok
          end
        rescue
          e -> 
            {:error, e}
        catch
          :exit, {:normal, _} -> 
            # El proceso terminó normalmente (cancelación exitosa)
            :ok
          :exit, exit_reason -> 
            {:error, exit_reason}
        end

      [] ->
        {:error, :trip_not_found}
    end
  end

  @doc "Limpia viajes huérfanos que no pertenecen a ningún usuario activo"
  def cleanup_orphan_trips do
    # Buscar todos los viajes en el Registry
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

    # Verificar cada viaje y terminar los que no tienen un cliente válido
    Enum.each(trips_pids, fn pid ->
      try do
        # Verificar si el proceso del cliente todavía existe
        case GenServer.call(pid, :get_client_pid, 500) do
          {:ok, client_pid} ->
            # Verificar si el proceso del cliente todavía está vivo
            if not Process.alive?(client_pid) do
              # El proceso del cliente ya no existe, obtener el nombre y terminar el viaje
              case GenServer.call(pid, :get_client_name, 500) do
                {:ok, client_name} ->
                  # Intentar cancelar el viaje (puede terminar normalmente, eso está bien)
                  try do
                    GenServer.call(pid, {:cancel, client_name, "Cliente desconectado"}, 500)
                  rescue
                    _ -> :ok
                  catch
                    :exit, {:normal, _} -> :ok  # Terminación normal, está bien
                    :exit, _ -> :ok
                    _, _ -> :ok
                  end
                _ -> :ok
              end
            end
          _ -> :ok
        end
      rescue
        _ -> :ok
      catch
        :exit, {:normal, _} -> :ok  # El proceso terminó normalmente, está bien
        :exit, _ -> :ok
        _, _ -> :ok
      end
    end)
    
    :ok
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