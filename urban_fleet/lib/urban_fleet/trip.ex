defmodule UrbanFleet.Trip do
  use GenServer

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
    GenServer.start_link(__MODULE__, {client_pid, client_name, origin, destination}, [])
  end

  # --- Callbacks GenServer ---
  @impl true
  def init({client_pid, client_name, origin, destination}) do
    # Genera un ID único y lo registra en el Registry
    trip_id = System.unique_integer([:positive])
    case Registry.register(Registry.UrbanFleet, "trip_#{trip_id}", self()) do
      {:error, _reason} -> 
        {:stop, :registration_failed}
      {:ok, _value} -> 
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

        {:ok, state}
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
  def handle_call(:get_status, _from, state) do
    status_info = %{
      id: state.id,
      origin: state.origin,
      destination: state.destination,
      status: state.status
    }
    {:reply, {:ok, status_info}, state}
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
    # 1. Asignar puntos
    UrbanFleet.UserManager.update_score(state.client_name, 10)
    UrbanFleet.UserManager.update_score(state.driver_name, 15)

    # 2. Registrar el viaje completado
    UrbanFleet.TripLogger.log_trip(
      state.client_name,
      state.driver_name,
      state.origin,
      state.destination,
      "Completado"
    )

    # 3. Notificar a ambos
    send(state.client_pid, {:trip_completed, state.id, state.driver_name})
    send(state.driver_pid, {:trip_completed, state.id, state.client_name})

    # 4. Terminar el proceso
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Asegurarnos de que el ID se elimine del Registry
    Registry.unregister(Registry.UrbanFleet, "trip_#{state.id}")
    :ok
  end
end