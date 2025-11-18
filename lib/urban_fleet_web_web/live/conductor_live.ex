defmodule UrbanFleetWebWeb.ConductorLive do
  use UrbanFleetWebWeb, :live_view

  # --- 1. Inicialización ---
  # Esto es como el "connect" y "go_online" de tu CLI
  @impl true
  def mount(params, session, socket) do
    # Obtener username de los parámetros de la URL o de la sesión
    username = Map.get(params, "user") || socket.assigns[:current_user] || Map.get(session, "username")
    
    if username do
      # Suscribe esta LiveView (que es un proceso) a las notificaciones
      UrbanFleet.Server.go_online(self())

      # Obtener el puntaje del conductor
      score = case UrbanFleet.Server.my_score(username) do
        {:ok, s} -> s
        _ -> 0
      end

      socket =
        assign(socket,
          conductor_name: username,
          score: score,
          trips: UrbanFleet.Server.list_trips(),
          status: "Online - Esperando viajes...",
          current_trip_id: nil,  # ID del viaje actual aceptado
          consecutive_trips: 0,  # Viajes consecutivos
          last_bonus: 0  # Último bono recibido
        )

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  # --- 2. Manejo de Notificaciones (PubSub) ---
  # ¡Esta es la misma función 'handle_info' de tu CLI!
  @impl true
  def handle_info({:new_trip_available, trip}, socket) do
    # Añadimos el nuevo viaje a la lista en la UI
    new_trips = [trip | socket.assigns.trips]
    
    socket = assign(socket, 
      trips: new_trips,
      status: "¡NUEVO VIAJE! ID: #{trip.id}"
    )
    
    {:noreply, socket}
  end

  @impl true
  def handle_info({:trip_completed, id, client_name, bonus, consecutive_trips}, socket) do
    # Actualizar el puntaje
    new_score = case UrbanFleet.Server.my_score(socket.assigns.conductor_name) do
      {:ok, s} -> s
      _ -> socket.assigns.score
    end
    
    bonus_msg = if bonus > 0, do: " ¡Bono de #{bonus} puntos por #{consecutive_trips} viajes consecutivos!", else: ""
    socket = assign(socket, 
      status: "Viaje #{id} con #{client_name} completado. ¡+15 puntos!#{bonus_msg}",
      score: new_score,
      current_trip_id: nil,  # Limpiar viaje actual
      consecutive_trips: consecutive_trips,
      last_bonus: bonus
    )
    {:noreply, socket}
  end

  @impl true
  def handle_info({:trip_completed, id, client_name}, socket) do
    # Compatibilidad con mensajes sin bono
    handle_info({:trip_completed, id, client_name, 0, 0}, socket)
  end

  @impl true
  def handle_info({:trip_cancelled, id, canceler_name, reason}, socket) do
    # Actualizar el puntaje en tiempo real si el conductor fue quien canceló
    new_score = if canceler_name == socket.assigns.conductor_name do
      case UrbanFleet.Server.my_score(socket.assigns.conductor_name) do
        {:ok, s} -> s
        _ -> socket.assigns.score
      end
    else
      socket.assigns.score
    end
    
    penalty_msg = if canceler_name == socket.assigns.conductor_name, do: " (Penalización aplicada)", else: ""
    
    socket = assign(socket,
      status: "⚠️ Viaje #{id} cancelado por #{canceler_name}: #{reason}#{penalty_msg}",
      score: new_score,
      current_trip_id: nil  # Limpiar viaje actual
    )
    {:noreply, socket}
  end
  
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}

  # --- 3. Manejo de Eventos (Clics) ---
  # Cuando el conductor haga clic en "Aceptar Viaje"
  @impl true
  def handle_event("accept_trip", %{"trip-id" => id_str}, socket) do
    {trip_id, _} = Integer.parse(id_str)
    driver_name = socket.assigns.conductor_name

    socket = case UrbanFleet.Server.accept_trip(self(), driver_name, trip_id) do
      :ok ->
        # Quitamos el viaje de la lista de pendientes
        trips = Enum.reject(socket.assigns.trips, &(&1.id == trip_id))
        assign(socket, 
          trips: trips,
          status: "¡Viaje #{trip_id} aceptado! En progreso...",
          current_trip_id: trip_id
        )

      {:error, reason} ->
        assign(socket, status: "Error al aceptar: #{reason}")
    end

    {:noreply, socket}
  end

  # Cancelar viaje actual
  @impl true
  def handle_event("cancel_trip", %{"reason" => reason}, socket) do
    if socket.assigns.current_trip_id do
      trip_id = socket.assigns.current_trip_id
      driver_name = socket.assigns.conductor_name
      
      case UrbanFleet.Server.cancel_trip(driver_name, trip_id, reason) do
        :ok ->
          # Actualizar el puntaje en tiempo real
          new_score = case UrbanFleet.Server.my_score(driver_name) do
            {:ok, s} -> s
            _ -> socket.assigns.score
          end
          
          socket = assign(socket,
            status: "⚠️ Viaje #{trip_id} cancelado. Razón: #{reason} (Penalización aplicada)",
            score: new_score,
            current_trip_id: nil
          )
          {:noreply, socket}
          
        {:error, reason} ->
          socket = assign(socket, status: "❌ Error al cancelar: #{reason}")
          {:noreply, socket}
      end
    else
      socket = assign(socket, status: "❌ No hay viaje activo para cancelar.")
      {:noreply, socket}
    end
  end
  
  # Desconectar
  @impl true
  def handle_event("disconnect", _params, socket) do
    # Desconectar del sistema
    UrbanFleet.Server.go_offline(self())
    
    socket = 
      socket
      |> put_flash(:info, "Desconectado exitosamente")
      |> push_navigate(to: ~p"/login")
    
    {:noreply, socket}
  end
end