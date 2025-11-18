defmodule UrbanFleet.Trip do
  use GenServer, restart: :temporary  # ⬅️ CRÍTICO: No reiniciar si crashea

  # Duración simulada del viaje
  @trip_duration_ms 20_000 # 20 segundos
  # Tiempo de expiración si nadie acepta
  @expiry_duration_ms 120_000 # 2 minutos

  # Estado del GenServer
  defstruct [
    :id,
    :client_pid,
    :client_name,
    :driver_pid,
    :driver_name,
    :origin,
    :destination,
    :status, # :pending, :in_progress, :completed, :expired
    :expiry_timer # Referencia al temporizador de expiración
  ]

  # --- API Pública ---
  def start_link({client_pid, client_name, origin, destination}) do
    IO.puts("🔍 TRIP.START_LINK - Client: #{client_name} - PID: #{inspect(client_pid)}")
    IO.puts("🔍 TRIP.START_LINK - Origin: #{origin}, Destination: #{destination}")
    result = GenServer.start_link(__MODULE__, {client_pid, client_name, origin, destination}, [])
    IO.puts("🔍 TRIP.START_LINK - Resultado: #{inspect(result)}")
    result
  end

  # --- Callbacks GenServer ---
  @impl true
  def init({client_pid, client_name, origin, destination}) do
    trip_id = System.unique_integer([:positive])
    IO.puts("🔍 TRIP.INIT - Creando viaje ID: #{trip_id} para #{client_name}")
    
    # 🔒 VALIDACIÓN CRÍTICA: Verificar que los campos no estén vacíos
    cond do
      is_nil(origin) or origin == "" or is_nil(destination) or destination == "" ->
        IO.puts("❌ TRIP.INIT - ERROR: Parámetros inválidos (origen o destino vacío)")
        {:stop, :invalid_parameters}
      
      not (UrbanFleet.Location.is_valid?(origin) and UrbanFleet.Location.is_valid?(destination)) ->
        IO.puts("❌ TRIP.INIT - ERROR: Ubicaciones inválidas")
        {:stop, :invalid_locations}
      
      true ->
        # Genera un ID único y lo registra en el Registry
        case Registry.register(Registry.UrbanFleet, "trip_#{trip_id}", self()) do
          {:error, reason} -> 
            IO.puts("❌ TRIP.INIT - ERROR al registrar en Registry: #{inspect(reason)}")
            {:stop, :registration_failed}
          {:ok, _value} -> 
            IO.puts("✅ TRIP.INIT - Viaje #{trip_id} registrado exitosamente en Registry")
            # Inicia el temporizador de expiración
            expiry_timer = Process.send_after(self(), :expire, @expiry_duration_ms)

            state = %__MODULE__{
              id: trip_id,
              client_pid: client_pid,
              client_name: client_name,
              origin: origin,
              destination: destination,
              status: :pending,
              expiry_timer: expiry_timer
            }

            IO.puts("✅ TRIP.INIT - Estado inicializado: ID=#{trip_id}, Origin=#{origin}, Dest=#{destination}")
            {:ok, state}
        end
    end
  end

  @doc "Llamado por el conductor para aceptar el viaje"
  @impl true
  def handle_call({:accept, driver_pid, driver_name}, _from, state) do
    # Solo se puede aceptar si está pendiente
    if state.status == :pending do
      # 1. Cancelar el temporizador de expiración
      Process.cancel_timer(state.expiry_timer)

      # 2. Iniciar el temporizador de duración del viaje
      Process.send_after(self(), :trip_complete, @trip_duration_ms)

      # 3. Actualizar estado
      updated_state = %{
        state
        | status: :in_progress,
          driver_pid: driver_pid,
          driver_name: driver_name,
          expiry_timer: nil
      }

      # 4. Notificar al cliente
      send(state.client_pid, {:trip_accepted, driver_name})

      {:reply, :ok, updated_state}
    else
      {:reply, {:error, :trip_not_available}, state}
    end
  end

  @impl true
  def handle_call({:cancel, canceler_name, reason}, _from, state) do
    # Validar que el cancelador sea el cliente o el conductor del viaje
    # Comparación case-insensitive para mayor robustez
    canceler_normalized = canceler_name |> String.trim() |> String.downcase()
    client_normalized = state.client_name |> String.trim() |> String.downcase()
    driver_normalized = if state.driver_name, do: state.driver_name |> String.trim() |> String.downcase(), else: nil
    
    if canceler_normalized != client_normalized and canceler_normalized != driver_normalized do
      {:reply, {:error, :unauthorized}, state}
    else
      cond do
        state.status == :pending ->
        # Cancelar el temporizador de expiración para evitar penalización doble
        if state.expiry_timer do
          Process.cancel_timer(state.expiry_timer)
        end
        
        # Cancelación antes de aceptar - penalización menor SOLO si el cliente cancela
        # NO penalizar si el viaje simplemente no fue aceptado (eso se maneja con expire)
        penalty = if canceler_name == state.client_name, do: -3, else: 0
        if penalty < 0 do
          UrbanFleet.UserManager.update_score(canceler_name, penalty)
        end

        # Notificar al otro participante si existe
        if state.driver_pid do
          send(state.driver_pid, {:trip_cancelled, state.id, canceler_name, reason})
        end
        send(state.client_pid, {:trip_cancelled, state.id, canceler_name, reason})

        UrbanFleet.TripLogger.log_trip(
          state.client_name,
          state.driver_name || "N/A",
          state.origin,
          state.destination,
          "Cancelado por #{canceler_name}: #{reason}"
        )

        {:stop, :normal, state}

      state.status == :in_progress ->
        # Cancelación durante el viaje - penalización mayor
        penalty = if canceler_name == state.client_name, do: -10, else: -15
        UrbanFleet.UserManager.update_score(canceler_name, penalty)

        # Resetear contador de viajes consecutivos del conductor si cancela
        if canceler_name == state.driver_name do
          UrbanFleet.DriverStats.reset_consecutive(state.driver_name)
        end

        # Notificar al otro participante
        other_pid = if canceler_name == state.client_name, do: state.driver_pid, else: state.client_pid
        if other_pid do
          send(other_pid, {:trip_cancelled, state.id, canceler_name, reason})
        end

        UrbanFleet.TripLogger.log_trip(
          state.client_name,
          state.driver_name,
          state.origin,
          state.destination,
          "Cancelado durante viaje por #{canceler_name}: #{reason}"
        )

        {:stop, :normal, state}

        true ->
          {:reply, {:error, :cannot_cancel}, state}
      end
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status_info = %{
      id: state.id,
      origin: state.origin,
      destination: state.destination,
      status: state.status
    }
    {:reply, {:ok, status_info}, state}
  end

  @impl true
  def handle_call(:get_client_pid, _from, state) do
    {:reply, {:ok, state.client_pid}, state}
  end

  @impl true
  def handle_call(:get_client_name, _from, state) do
    {:reply, {:ok, state.client_name}, state}
  end

  @doc "Se activa si el temporizador de 2 minutos expira"
  @impl true
  def handle_info(:expire, state) do
    # Solo expira si seguía pendiente
    if state.status == :pending do
      # 1. Penalizar al cliente
      UrbanFleet.UserManager.update_score(state.client_name, -5)

      # 2. Registrar el viaje expirado
      UrbanFleet.TripLogger.log_trip(
        state.client_name,
        "N/A",
        state.origin,
        state.destination,
        "Expirado"
      )

      # 3. Notificar al cliente
      send(state.client_pid, {:trip_expired, state.id})

      # 4. Terminar el proceso
      {:stop, :normal, state}
    else
      # El viaje ya fue aceptado, ignorar expiración
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:trip_complete, state) do
    # 1. Asignar puntos base
    UrbanFleet.UserManager.update_score(state.client_name, 10)
    base_driver_points = 15
    UrbanFleet.UserManager.update_score(state.driver_name, base_driver_points)

    # 2. Calcular bono por viajes consecutivos
    {consecutive_trips, bonus} = UrbanFleet.DriverStats.record_trip_completion(state.driver_name)
    if bonus > 0 do
      UrbanFleet.UserManager.update_score(state.driver_name, bonus)
    end

    # 3. Registrar el viaje completado
    UrbanFleet.TripLogger.log_trip(
      state.client_name,
      state.driver_name,
      state.origin,
      state.destination,
      "Completado"
    )

    # 4. Notificar a ambos (incluyendo información del bono)
    send(state.client_pid, {:trip_completed, state.id, state.driver_name})
    send(state.driver_pid, {:trip_completed, state.id, state.client_name, bonus, consecutive_trips})

    # 5. Terminar el proceso
    {:stop, :normal, state}
  end

  @impl true
  def terminate(reason, state) do
    IO.puts("🔴 TRIP #{state.id} TERMINANDO - Razón: #{inspect(reason)}")
    # Asegurarnos de que el ID se elimine del Registry
    Registry.unregister(Registry.UrbanFleet, "trip_#{state.id}")
    :ok
  end
end