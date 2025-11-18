defmodule UrbanFleetWebWeb.ClienteLive do
  use UrbanFleetWebWeb, :live_view

  # --- Funciones Helper ---
  
  # Función helper para obtener y validar los viajes del cliente
  defp get_validated_client_trips(client_pid, username) do
    # Obtener viajes del servidor
    all_trips_raw = UrbanFleet.Server.list_client_trips(client_pid, username)
    
    # Normalizar username para comparación
    username_normalized = username |> String.trim() |> String.downcase()
    
    # Validación adicional: verificar que cada viaje realmente pertenece al usuario
    Enum.filter(all_trips_raw, fn trip ->
      try do
        case Registry.lookup(Registry.UrbanFleet, "trip_#{trip.id}") do
          [{pid, _}] ->
            case GenServer.call(pid, :get_client_name, 500) do
              {:ok, trip_client_name} ->
                trip_client_name_normalized = trip_client_name |> String.trim() |> String.downcase()
                trip_client_name_normalized == username_normalized
              _ -> false
            end
          [] -> false
        end
      rescue
        _ -> false
      catch
        _ -> false
      end
    end)
  end

  # --- 1. Inicialización ---
  @impl true
  def mount(params, session, socket) do
    # Obtener username de los parámetros de la URL o de la sesión
    username = Map.get(params, "user") || socket.assigns[:current_user] || Map.get(session, "username")
    
    if username do
      # Normalizar el username para asegurar consistencia
      username = username |> String.trim()
      
      # Formateamos las ubicaciones para el menú desplegable
      locations = UrbanFleet.Location.all() |> Enum.map(&{&1, &1})

      # Crear un formulario vacío
      form = to_form(%{}, as: :trip)
      
      # Obtener el puntaje del usuario
      score = case UrbanFleet.Server.my_score(username) do
        {:ok, s} -> s
        _ -> 0
      end

      # Limpiar viajes huérfanos antes de obtener los viajes del usuario
      # (esto ayuda a eliminar viajes de sesiones anteriores)
      # Ejecutar en background para no bloquear el mount
      try do
        UrbanFleet.Server.cleanup_orphan_trips()
      rescue
        _ -> :ok
      catch
        _ -> :ok
      end

      # Obtener todos los viajes activos del cliente (con validación por username)
      client_trips = get_validated_client_trips(self(), username)
      
      current_trip = List.first(client_trips)
      current_trip_id = if current_trip, do: current_trip.id, else: nil

      socket =
        assign(socket,
          username: username,
          score: score,
          locations: locations,
          status: if(current_trip_id, do: "Viaje #{current_trip_id} activo", else: "Lista para pedir un viaje."),
          form: form,
          current_trip_id: current_trip_id,  # ID del viaje actual (si existe)
          all_trips: client_trips  # Lista de todos los viajes del cliente
        )

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  # --- 2. Manejo de Eventos (Clics) ---
  # Se activa cuando el cliente envía el formulario "Pedir Viaje"
  @impl true
  def handle_event("request_trip", %{"trip" => %{"origin" => origin, "destination" => dest}}, socket) do
    username = socket.assigns.username

    # 1. Validar que no sean la misma ubicación
    if origin == dest do
      socket = assign(socket, status: "❌ Error: El origen y destino no pueden ser iguales.")
      {:noreply, socket}
    else
      # 2. Si hay un viaje anterior activo, cancelarlo primero (solo si realmente pertenece al usuario)
      socket = if socket.assigns.current_trip_id do
        old_trip_id = socket.assigns.current_trip_id
        # Intentar cancelar el viaje anterior silenciosamente (solo si pertenece al usuario)
        case UrbanFleet.Server.cancel_trip(username, old_trip_id, "Reemplazado por nuevo viaje") do
          :ok -> socket
          {:error, :unauthorized} -> 
            # El viaje no pertenece al usuario, ignorar
            socket
          _ -> socket
        end
      else
        socket
      end
      
      # 3. Llamar a nuestro backend para crear el nuevo viaje
      case UrbanFleet.Server.request_trip(self(), username, origin, dest) do
        {:ok, trip_id} ->
          # Recargar lista de viajes después de crear uno nuevo (con validación por username)
          client_trips = get_validated_client_trips(self(), username)
          
          socket = assign(socket, 
            status: "✅ ¡Viaje #{trip_id} solicitado! Buscando conductor...",
            current_trip_id: trip_id,
            all_trips: client_trips
          )
          {:noreply, socket}

        {:error, :location_invalid} ->
          socket = assign(socket, status: "❌ Error: Ubicación inválida.")
          {:noreply, socket}
          
        {:error, reason} ->
          socket = assign(socket, status: "❌ Error: #{reason}")
          {:noreply, socket}
      end
    end
  end
  
  # Cancelar viaje (puede ser por ID específico o el actual)
  @impl true
  def handle_event("cancel_trip", %{"reason" => reason} = params, socket) do
    username = socket.assigns.username
    trip_id_str = Map.get(params, "trip-id") || socket.assigns.current_trip_id
    
    if trip_id_str do
      # Convertir trip_id a entero si es string
      trip_id = if is_binary(trip_id_str), do: String.to_integer(trip_id_str), else: trip_id_str
      
      case UrbanFleet.Server.cancel_trip(username, trip_id, reason) do
        :ok ->
          # Actualizar el puntaje en tiempo real
          new_score = case UrbanFleet.Server.my_score(username) do
            {:ok, s} -> s
            _ -> socket.assigns.score
          end
          
          # Recargar lista de viajes (solo los que realmente pertenecen al usuario)
          client_trips = get_validated_client_trips(self(), username)
          current_trip = List.first(client_trips)
          current_trip_id = if current_trip, do: current_trip.id, else: nil
          
          socket = assign(socket,
            status: "⚠️ Viaje #{trip_id} cancelado. Razón: #{reason} (Penalización aplicada)",
            score: new_score,
            current_trip_id: current_trip_id,
            all_trips: client_trips
          )
          {:noreply, socket}
          
        {:error, :unauthorized} ->
          # Si no tiene permiso, recargar la lista para eliminar el viaje de la vista
          client_trips = UrbanFleet.Server.list_client_trips(self(), username)
          socket = assign(socket, 
            status: "❌ No tienes permiso para cancelar este viaje. Se ha eliminado de tu lista.",
            all_trips: client_trips
          )
          {:noreply, socket}
        {:error, reason} ->
          error_msg = if is_binary(reason), do: reason, else: inspect(reason)
          socket = assign(socket, status: "❌ Error al cancelar: #{error_msg}")
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
    socket = 
      socket
      |> put_flash(:info, "Desconectado exitosamente")
      |> push_navigate(to: ~p"/login")
    
    {:noreply, socket}
  end

  # --- 3. Manejo de Notificaciones (Mensajes del GenServer) ---

  # El GenServer 'Trip' nos avisa que fue aceptado
  @impl true
  def handle_info({:trip_accepted, driver_name}, socket) do
    socket = assign(socket, status: "🟢 ¡Aceptado por #{driver_name}! El viaje está en curso.")
    {:noreply, socket}
  end

  # El GenServer 'Trip' nos avisa que terminó
  @impl true
  def handle_info({:trip_completed, id, driver_name}, socket) do
    # Actualizar el puntaje
    new_score = case UrbanFleet.Server.my_score(socket.assigns.username) do
      {:ok, s} -> s
      _ -> socket.assigns.score
    end
    
    # Recargar lista de viajes
    client_trips = UrbanFleet.Server.list_client_trips(self(), socket.assigns.username)
    current_trip = List.first(client_trips)
    current_trip_id = if current_trip, do: current_trip.id, else: nil
    
    socket = assign(socket, 
      status: "🎉 ¡Viaje #{id} con #{driver_name} completado! ¡+10 puntos!",
      score: new_score,
      current_trip_id: current_trip_id,
      all_trips: client_trips
    )
    {:noreply, socket}
  end

  # El GenServer 'Trip' nos avisa que expiró
  @impl true
  def handle_info({:trip_expired, id}, socket) do
    # Actualizar el puntaje
    new_score = case UrbanFleet.Server.my_score(socket.assigns.username) do
      {:ok, s} -> s
      _ -> socket.assigns.score
    end
    
    # Recargar lista de viajes
    client_trips = UrbanFleet.Server.list_client_trips(self(), socket.assigns.username)
    current_trip = List.first(client_trips)
    current_trip_id = if current_trip, do: current_trip.id, else: nil
    
    socket = assign(socket, 
      status: "🔴 Tu viaje #{id} expiró sin conductor. ¡-5 puntos!",
      score: new_score,
      current_trip_id: current_trip_id,
      all_trips: client_trips
    )
    {:noreply, socket}
  end
  
  # El GenServer 'Trip' nos avisa que fue cancelado
  @impl true
  def handle_info({:trip_cancelled, id, canceler_name, reason}, socket) do
    penalty_msg = if canceler_name == socket.assigns.username, do: " (Penalización aplicada)", else: ""
    
    # Actualizar el puntaje en tiempo real si el cliente fue quien canceló
    new_score = if canceler_name == socket.assigns.username do
      case UrbanFleet.Server.my_score(socket.assigns.username) do
        {:ok, s} -> s
        _ -> socket.assigns.score
      end
    else
      socket.assigns.score
    end
    
    # Recargar lista de viajes (con manejo de errores por si algún proceso ya terminó)
    client_trips = try do
      get_validated_client_trips(self(), socket.assigns.username)
    rescue
      _ -> []
    catch
      _ -> []
    end
    
    current_trip = List.first(client_trips)
    current_trip_id = if current_trip, do: current_trip.id, else: nil
    
    socket = assign(socket,
      status: "⚠️ Tu viaje #{id} fue cancelado por #{canceler_name}: #{reason}#{penalty_msg}",
      score: new_score,
      current_trip_id: current_trip_id,
      all_trips: client_trips
    )
    {:noreply, socket}
  end

  # Ignorar otros mensajes
  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
end