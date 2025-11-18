defmodule UrbanFleet.Supervisor do
  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Si un 'Trip' falla, solo se reinicia ese 'Trip'
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # --- API Pública ---
  @doc "Inicia un nuevo GenServer 'Trip'"
  def start_trip(client_pid, client_name, origin, destination) do
    spec = {UrbanFleet.Trip, {client_pid, client_name, origin, destination}}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end