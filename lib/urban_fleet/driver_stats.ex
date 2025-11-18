defmodule UrbanFleet.DriverStats do
  @moduledoc """
  Módulo para rastrear estadísticas de conductores y calcular bonos por viajes consecutivos
  """
  use GenServer

  defstruct [
    :driver_name,
    :consecutive_trips,  # Número de viajes consecutivos
    :last_trip_time,     # Timestamp del último viaje completado
    :total_trips_today    # Total de viajes hoy
  ]

  # --- API Pública ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Registra que un conductor completó un viaje"
  def record_trip_completion(driver_name) do
    GenServer.call(__MODULE__, {:trip_completed, driver_name})
  end

  @doc "Obtiene el número de viajes consecutivos de un conductor"
  def get_consecutive_trips(driver_name) do
    GenServer.call(__MODULE__, {:get_consecutive, driver_name})
  end

  @doc "Calcula el bono por viajes consecutivos"
  def calculate_bonus(consecutive_trips) do
    cond do
      consecutive_trips >= 5 -> 10  # Bono de 10 puntos por 5+ viajes consecutivos
      consecutive_trips >= 3 -> 5    # Bono de 5 puntos por 3+ viajes consecutivos
      true -> 0
    end
  end

  @doc "Resetea el contador de viajes consecutivos (cuando el conductor se desconecta o pasa mucho tiempo)"
  def reset_consecutive(driver_name) do
    GenServer.cast(__MODULE__, {:reset_consecutive, driver_name})
  end

  # --- Callbacks GenServer ---
  @impl true
  def init(_opts) do
    {:ok, %{}}  # Estado: mapa de driver_name -> %DriverStats{}
  end

  @impl true
  def handle_call({:trip_completed, driver_name}, _from, state) do
    now = System.system_time(:second)
    stats = Map.get(state, driver_name, %__MODULE__{
      driver_name: driver_name,
      consecutive_trips: 0,
      last_trip_time: 0,
      total_trips_today: 0
    })

    # Si pasaron más de 30 minutos desde el último viaje, resetear contador
    time_since_last = now - stats.last_trip_time
    consecutive = if time_since_last > 1800, do: 1, else: stats.consecutive_trips + 1

    updated_stats = %{
      stats
      | consecutive_trips: consecutive,
        last_trip_time: now,
        total_trips_today: stats.total_trips_today + 1
    }

    bonus = calculate_bonus(consecutive)
    new_state = Map.put(state, driver_name, updated_stats)

    {:reply, {consecutive, bonus}, new_state}
  end

  @impl true
  def handle_call({:get_consecutive, driver_name}, _from, state) do
    stats = Map.get(state, driver_name)
    consecutive = if stats, do: stats.consecutive_trips, else: 0
    {:reply, consecutive, state}
  end

  @impl true
  def handle_cast({:reset_consecutive, driver_name}, state) do
    stats = Map.get(state, driver_name)
    if stats do
      updated_stats = %{stats | consecutive_trips: 0}
      new_state = Map.put(state, driver_name, updated_stats)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
end

