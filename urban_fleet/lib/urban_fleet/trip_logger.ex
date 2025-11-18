defmodule UrbanFleet.TripLogger do
  use GenServer

  @results_file "lib/data/results.log"

  # --- API Pública ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @results_file, name: __MODULE__)
  end

  @doc "Registra un viaje completado"
  def log_trip(client, driver, origin, dest, status) do
    timestamp = DateTime.utc_now() |> DateTime.to_string()
    log_entry =
      "#{timestamp}; cliente=#{client}; conductor=#{driver}; origen=#{origin}; destino=#{dest}; status=#{status}\n"

    # Usamos 'cast' porque no necesitamos esperar una respuesta
    GenServer.cast(__MODULE__, {:log, log_entry})
  end

  # --- Callbacks GenServer ---
  @impl true
  def init(file_path) do
    {:ok, file_path}
  end

  @impl true
  def handle_cast({:log, log_entry}, file_path) do
    # 'append' es la operación clave aquí
    File.write(file_path, log_entry, [:append])
    {:noreply, file_path}
  end
end