defmodule UrbanFleet.CLI do
  # El 'estado' de nuestra CLI
  @initial_state %{
    username: nil,
    role: nil,
    online: false, # Solo para conductores
    pid: self()
  }

  def main(_args) do
    IO.puts("--- Bienvenido a UrbanFleet CLI ---")
    IO.puts("Comandos disponibles:")
    IO.puts("  connect <usuario> <pass>")
    IO.puts("  request_trip <origen> <destino>")
    IO.puts("  list_trips")
    IO.puts("  accept_trip <id_viaje>")
    IO.puts("  go_online / go_offline")
    IO.puts("  my_score / show_ranking")
    IO.puts("-------------------------------------")

    # Inicia el bucle de comandos, pasando el estado inicial
    command_loop(@initial_state)
  end

  # Bucle principal que lee comandos
  defp command_loop(state) do
    # Espera por un comando O un mensaje de PubSub/GenServer
    receive do
      msg ->
        # Maneja mensajes asíncronos (notificaciones)
        handle_async_message(msg, state)
        command_loop(state)
    after
      0 ->
        # Si no hay mensajes, pide el siguiente comando
        prompt(state) |> parse_command(state) |> handle_command() |> command_loop()
    end
  end

  defp prompt(state) do
    prefix =
      cond do
        state.role == "conductor" and state.online -> "[ONLINE] "
        state.role == "conductor" and not state.online -> "[OFFLINE] "
        state.username -> "[#{state.username}] "
        true -> ""
      end

    IO.gets("> #{prefix}") |> String.trim()
  end

  # --- Manejo de Comandos ---

  defp parse_command(input, state) do
    parts = String.split(input, " ")
    cmd = Enum.at(parts, 0) || ""
    args = Enum.drop(parts, 1) || []
    {cmd, args, state}
  end

  defp handle_command({"connect", [username, pass], state}) do
    case UrbanFleet.Server.connect(username, pass) do
      {:ok, type, role} ->
        IO.puts("✅ #{type} exitoso. Eres: #{role}")
        %{state | username: username, role: role}

      {:error, reason} ->
        IO.puts("❌ Error: #{reason}")
        state
    end
  end

  defp handle_command({"go_online", [], %{role: "conductor"} = state}) do
    case UrbanFleet.Server.go_online(state.pid) do
      :ok ->
        IO.puts("🟢 Estás 'online'. Esperando notificaciones de viaje...")
        %{state | online: true}
      {:error, reason} ->
        IO.puts("❌ Error al ponerse online: #{reason}")
        state
    end
  end

  defp handle_command({"go_offline", [], %{role: "conductor"} = state}) do
    :ok = UrbanFleet.Server.go_offline(state.pid)
    IO.puts("🔴 Estás 'offline'.")
    %{state | online: false}
  end

  defp handle_command({"request_trip", [origin, dest], %{role: "cliente"} = state}) do
    IO.puts("Solicitando viaje de #{origin} a #{dest}...")
    case UrbanFleet.Server.request_trip(state.pid, state.username, origin, dest) do
      {:ok, trip_id} ->
        IO.puts("✅ Viaje creado (ID: #{trip_id}). Esperando conductor...")
        state

      {:error, :location_invalid} ->
        IO.puts("❌ Error: Ubicación inválida.")
        state

      {:error, reason} ->
        IO.puts("❌ Error: #{reason}")
        state
    end
  end

  defp handle_command({"list_trips", [], %{role: "conductor", online: true} = state}) do
    trips = UrbanFleet.Server.list_trips()
    IO.puts("--- Viajes Pendientes ---")
    if Enum.empty?(trips) do
      IO.puts("No hay viajes disponibles.")
    else
      Enum.each(trips, fn trip ->
        IO.puts("  ID: #{trip.id} | #{trip.origin} -> #{trip.destination}")
      end)
    end
    state
  end

  defp handle_command({"accept_trip", [id_str], %{role: "conductor", online: true} = state}) do
    {trip_id, _} = Integer.parse(id_str)
    IO.puts("Aceptando viaje #{trip_id}...")
    case UrbanFleet.Server.accept_trip(state.pid, state.username, trip_id) do
      :ok ->
        IO.puts("✅ ¡Viaje aceptado! Simulando duración de 20s...")
        state

      {:error, :trip_not_available} ->
        IO.puts("❌ ¡Tarde! Alguien más aceptó el viaje.")
        state

      {:error, :trip_not_found} ->
        IO.puts("❌ Viaje no encontrado o ya no está disponible.")
        state
    end
  end

  defp handle_command({"my_score", [], state}) do
    {:ok, score} = UrbanFleet.Server.my_score(state.username)
    IO.puts("Tu puntaje actual: #{score}")
    state
  end

  defp handle_command({"show_ranking", [], state}) do
    {:ok, %{clients: c, drivers: d}} = UrbanFleet.Server.show_ranking()
    IO.puts("--- 🏆 Ranking Conductores ---")
    Enum.each(d, fn u -> IO.puts("  #{u.username} (#{u.score} pts)") end)
    IO.puts("--- 🏆 Ranking Clientes ---")
    Enum.each(c, fn u -> IO.puts("  #{u.username} (#{u.score} pts)") end)
    state
  end

  defp handle_command({"exit", _, _}), do: System.stop()
  defp handle_command({"", _, state}), do: state # Ignora comandos vacíos
  defp handle_command({cmd, _args, state}) when is_binary(cmd) and cmd != "" do
    IO.puts("❌ Comando no reconocido: '#{cmd}'. Escribe 'exit' para salir.")
    state
  end
  defp handle_command(_other) do
    IO.puts("Comando no reconocido o inválido.")
    @initial_state
  end

  # --- Manejo de Mensajes Asíncronos ---

  # --- Manejo de Mensajes Asíncronos ---

  # Conductor: Recibe notificación de nuevo viaje (PubSub)
  # CAMBIA ESTA FUNCIÓN:
  defp handle_async_message({:new_trip_available, trip}, _state) do
    IO.puts("\n❗️ NUEVO VIAJE: ID #{trip.id} | #{trip.origin} -> #{trip.destination}")
    IO.puts("Usa 'accept_trip #{trip.id}' para aceptarlo.")
  end


  # Cliente: Su viaje fue aceptado
  defp handle_async_message({:trip_accepted, driver_name}, _state) do
    IO.puts("\n✅ ¡Un conductor aceptó tu viaje!")
    IO.puts("Conductor: #{driver_name}. El viaje está en progreso...")
  end

  # Cliente o Conductor: El viaje terminó
  defp handle_async_message({:trip_completed, id, other_party}, state) do
    role = if state.role == "cliente", do: "conductor", else: "cliente"
    IO.puts("\n🎉 ¡Viaje #{id} completado!")
    IO.puts("El #{role} fue #{other_party}.")
    IO.puts("Se han asignado puntos. Revisa con 'my_score'.")
  end

  # Cliente: El viaje expiró
  defp handle_async_message({:trip_expired, id}, _state) do
    IO.puts("\n❌ Tu viaje #{id} expiró sin encontrar conductor.")
    IO.puts("Has perdido 5 puntos.")
  end

  # Ignorar otros mensajes
  defp handle_async_message(_msg, _state), do: nil
end