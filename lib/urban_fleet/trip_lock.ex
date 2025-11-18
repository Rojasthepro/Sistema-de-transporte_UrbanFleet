defmodule UrbanFleet.TripLock do
  @moduledoc """
  GenServer que mantiene un bloqueo por usuario para prevenir la creación
  simultánea de múltiples viajes por el mismo usuario.
  """
  use GenServer

  # --- API Pública ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc "Intenta adquirir un bloqueo para crear un viaje. Retorna :ok si se adquirió, {:error, :locked} si ya está bloqueado"
  def acquire_lock(username) do
    GenServer.call(__MODULE__, {:acquire_lock, username})
  end

  @doc "Libera el bloqueo para un usuario"
  def release_lock(username) do
    GenServer.cast(__MODULE__, {:release_lock, username})
  end

  # --- Callbacks GenServer ---
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:acquire_lock, username}, _from, state) do
    username_normalized = username |> String.trim() |> String.downcase()
    IO.puts("🔒 TRIP_LOCK.ACQUIRE - Username: #{username_normalized}, Estado actual: #{inspect(Map.get(state, username_normalized))}")
    
    if Map.has_key?(state, username_normalized) do
      IO.puts("🔒 TRIP_LOCK.ACQUIRE - BLOQUEADO para #{username_normalized}")
      {:reply, {:error, :locked}, state}
    else
      # Adquirir el bloqueo
      new_state = Map.put(state, username_normalized, :os.system_time(:millisecond))
      IO.puts("🔒 TRIP_LOCK.ACQUIRE - BLOQUEO ADQUIRIDO para #{username_normalized}")
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_cast({:release_lock, username}, state) do
    username_normalized = username |> String.trim() |> String.downcase()
    IO.puts("🔓 TRIP_LOCK.RELEASE - Liberando bloqueo para #{username_normalized}")
    new_state = Map.delete(state, username_normalized)
    {:noreply, new_state}
  end
end

