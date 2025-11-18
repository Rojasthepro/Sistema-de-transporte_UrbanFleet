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
    IO.puts("🔍 SUPERVISOR.START_TRIP - Client: #{client_name} - PID: #{inspect(client_pid)}")
    IO.puts("🔍 SUPERVISOR.START_TRIP - Origin: #{origin}, Destination: #{destination}")
    IO.puts("🔍 SUPERVISOR.START_TRIP - Stack trace:")
    IO.inspect(Process.info(self(), :current_stacktrace), label: "Stack")
    
    # ⬅️ ESPECIFICAR restart: :temporary
    spec = %{
      id: UrbanFleet.Trip,
      start: {UrbanFleet.Trip, :start_link, [{client_pid, client_name, origin, destination}]},
      restart: :temporary  # ⬅️ CRÍTICO: No reiniciar si crashea
    }
    
    result = DynamicSupervisor.start_child(__MODULE__, spec)
    IO.puts("🔍 RESULTADO START_CHILD: #{inspect(result)}")
    result
  end
end