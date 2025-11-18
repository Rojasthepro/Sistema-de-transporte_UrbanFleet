defmodule UrbanFleetWebWeb.ClienteLive do
  use UrbanFleetWebWeb, :live_view

  # --- Funciones Helper ---
  
  # Función helper para obtener y validar los viajes del cliente
  defp get_validated_client_trips(client_pid, username) do
    # Normalizar username ANTES de todo
    username_normalized = username |> String.trim() |> String.downcase()
    
    # Obtener viajes del servidor
    all_trips_raw = UrbanFleet.Server.list_client_trips(client_pid, username)
    
    # ⚠️ PRIMERO: Eliminar duplicados por ID ANTES de validar (evita trabajo innecesario)
    unique_trips = all_trips_raw |> Enum.uniq_by(& &1.id)
    
    # Validación adicional: verificar que cada viaje realmente pertenece al usuario
    validated_trips = Enum.filter(unique_trips, fn trip ->
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
    
    # ⚠️ SEGUNDA CAPA: Eliminar duplicados por ID nuevamente (por si acaso)
    validated_trips
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.id, :desc)  # Ordenar por ID descendente (más recientes primero)
  end

  # --- 1. Inicialización ---
  @impl true
  def mount(params, session, socket) do
    # Obtener username de los parámetros de la URL o de la sesión
    username = Map.get(params, "user") || socket.assigns[:current_user] || Map.get(session, "username")
    
    if username do
      # Normalizar el username para asegurar consistencia (trim + lowercase)
      username = username |> String.trim() |> String.downcase()
      
      # Formateamos las ubicaciones para el menú desplegable
      locations = UrbanFleet.Location.all() |> Enum.map(&{&1, &1})

      # Crear un formulario vacío
      form = to_form(%{}, as: :trip)
      
      # Solo hacer trabajo pesado si la conexión está lista (evita duplicados en mount estático)
      if connected?(socket) do
        # Obtener el puntaje del usuario
        score = case UrbanFleet.Server.my_score(username) do
          {:ok, s} -> s
          _ -> 0
        end

        # NOTA: Ya no llamamos a cleanup_orphan_trips porque elimina viajes válidos
        # de sesiones anteriores. Los viajes se filtran por username, no por client_pid,
        # por lo que los viajes de otras sesiones son válidos y deben mostrarse.

        # Obtener todos los viajes activos del cliente (con validación por username)
        # Esto incluye viajes de otras sesiones (filtrado por username, no por client_pid)
        client_trips = get_validated_client_trips(self(), username)
        
        # El current_trip_id es el primer viaje activo (pending o in_progress), no solo el primero de la lista
        current_trip = Enum.find(client_trips, fn trip -> 
          trip.status == :pending || trip.status == :in_progress 
        end)
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
        # Mount estático: solo asignar valores básicos
        socket =
          assign(socket,
            username: username,
            score: 0,
            locations: locations,
            status: "Cargando...",
            form: form,
            current_trip_id: nil,
            all_trips: []
          )
        {:ok, socket}
      end
    else
      {:ok, redirect(socket, to: ~p"/login")}
    end
  end

  # --- 2. Manejo de Eventos (Clics) ---
  # Se activa cuando el cliente envía el formulario "Pedir Viaje"
  @impl true
  def handle_event("request_trip", %{"trip" => %{"origin" => origin, "destination" => dest}}, socket) do
    IO.puts("🔍 CLIENTE_LIVE.REQUEST_TRIP - Username: #{socket.assigns.username}, Origin: #{origin}, Dest: #{dest}")
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()

    cond do
      # 1. Validar que los campos no estén vacíos
      is_nil(origin) or origin == "" or is_nil(dest) or dest == "" ->
        socket = assign(socket, status: "❌ Error: El origen y destino son requeridos.")
        {:noreply, socket}
      
      # 2. Validar origen/destino
      origin == dest ->
        socket = assign(socket, status: "❌ Error: El origen y destino no pueden ser iguales.")
        {:noreply, socket}
      
      # 3. BLOQUEO ESTRICTO: Si ya hay ID, NO permitir pedir otro
      socket.assigns.current_trip_id != nil ->
        # Verificar que el viaje realmente existe y está activo
        existing_trip = Enum.find(socket.assigns.all_trips || [], fn trip -> 
          trip.id == socket.assigns.current_trip_id && 
          (trip.status == :pending || trip.status == :in_progress)
        end)
        
        if existing_trip do
          msg = "⚠️ Ya tienes un viaje activo (#{socket.assigns.current_trip_id}). Debes completarlo o cancelarlo antes de pedir otro."
          {:noreply, assign(socket, status: msg)}
        else
          # El current_trip_id no corresponde a un viaje activo, limpiarlo y permitir crear uno nuevo
          socket = assign(socket, current_trip_id: nil)
          proceed_with_trip_creation(socket, username, origin, dest)
        end

      # 4. Proceder normalmente si no hay viaje
      true ->
        proceed_with_trip_creation(socket, username, origin, dest)
    end
  end
  
  # Función helper para crear un viaje (evita duplicar código)
  defp proceed_with_trip_creation(socket, username, origin, dest) do
    # 🔒 VERIFICACIÓN CRÍTICA: Doble check antes de crear
    # Obtener viajes frescos del servidor
    fresh_trips = get_validated_client_trips(self(), username)
    
    # Verificar si ya existe un viaje activo (pending o in_progress)
    existing_active_trip = Enum.find(fresh_trips, fn trip ->
      (trip.status == :pending || trip.status == :in_progress) &&
      trip.origin == origin &&
      trip.destination == dest
    end)
    
    if existing_active_trip do
      # Ya existe un viaje idéntico activo, no crear otro
      socket = assign(socket,
        status: "⚠️ Ya tienes un viaje activo hacia #{dest}. ID: #{existing_active_trip.id}",
        current_trip_id: existing_active_trip.id,
        all_trips: fresh_trips
      )
      {:noreply, socket}
    else
      # Proceder con la creación
      IO.puts("🔍 CLIENTE_LIVE.PROCEED - Llamando a Server.request_trip...")
      case UrbanFleet.Server.request_trip(self(), username, origin, dest) do
        {:ok, trip_id} ->
          # Recargar lista de viajes después de crear uno nuevo (con validación por username)
          # Esto incluye viajes de otras sesiones (filtrado por username, no por client_pid)
          client_trips = get_validated_client_trips(self(), username)
          
          socket = assign(socket, 
            status: "✅ ¡Viaje #{trip_id} solicitado! Buscando conductor...",
            current_trip_id: trip_id,  # El nuevo viaje es el actual
            all_trips: client_trips  # Mostrar TODOS los viajes del usuario (incluso de otras sesiones)
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
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()
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
          
          # Recargar lista de viajes (incluye viajes de otras sesiones, filtrado por username)
          client_trips = get_validated_client_trips(self(), username)
          
          # Buscar el siguiente viaje activo (pending o in_progress) después de cancelar
          # Si el viaje cancelado era el current_trip_id, buscar el siguiente activo
          current_trip = if socket.assigns.current_trip_id == trip_id do
            # El viaje cancelado era el actual, buscar el siguiente activo
            Enum.find(client_trips, fn trip -> 
              trip.status == :pending || trip.status == :in_progress 
            end)
          else
            # El viaje cancelado no era el actual, mantener el actual si sigue activo
            Enum.find(client_trips, fn trip -> 
              trip.id == socket.assigns.current_trip_id && 
              (trip.status == :pending || trip.status == :in_progress)
            end)
          end
          current_trip_id = if current_trip, do: current_trip.id, else: nil
          
          # ⚠️ CRÍTICO: Asegurar que current_trip_id sea nil si no hay viajes activos
          # Esto permite crear un nuevo viaje después de cancelar
          final_current_trip_id = if current_trip_id do
            # Verificar que el viaje realmente existe y está activo
            trip_exists = Enum.any?(client_trips, fn trip -> 
              trip.id == current_trip_id && 
              (trip.status == :pending || trip.status == :in_progress)
            end)
            if trip_exists, do: current_trip_id, else: nil
          else
            nil
          end
          
          socket = assign(socket,
            status: "⚠️ Viaje #{trip_id} cancelado. Razón: #{reason} (Penalización aplicada)",
            score: new_score,
            current_trip_id: final_current_trip_id,  # ⚠️ IMPORTANTE: Limpiar si no hay más viajes activos
            all_trips: client_trips  # Mostrar TODOS los viajes del usuario (incluso de otras sesiones)
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
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()
    
    # Recargar lista de viajes para reflejar el cambio de estado
    client_trips = get_validated_client_trips(self(), username)
    
    socket = assign(socket, 
      status: "🟢 ¡Aceptado por #{driver_name}! El viaje está en curso.",
      all_trips: client_trips
    )
    {:noreply, socket}
  end

  # El GenServer 'Trip' nos avisa que terminó
  @impl true
  def handle_info({:trip_completed, id, driver_name, _bonus, _consecutive_trips}, socket) do
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()
    
    # Actualizar el puntaje
    new_score = case UrbanFleet.Server.my_score(username) do
      {:ok, s} -> s
      _ -> socket.assigns.score
    end
    
    # Recargar lista de viajes (usando función validada para evitar duplicados)
    # Esto incluye viajes de otras sesiones (filtrado por username, no por client_pid)
    client_trips = get_validated_client_trips(self(), username)
    
    # Buscar el siguiente viaje activo (pending o in_progress) después de completar
    current_trip = Enum.find(client_trips, fn trip -> 
      trip.status == :pending || trip.status == :in_progress 
    end)
    current_trip_id = if current_trip, do: current_trip.id, else: nil
    
    socket = assign(socket, 
      status: "🎉 ¡Viaje #{id} con #{driver_name} completado! ¡+10 puntos!",
      score: new_score,
      current_trip_id: current_trip_id,  # ⚠️ IMPORTANTE: Limpiar si no hay más viajes activos
      all_trips: client_trips  # Mostrar TODOS los viajes del usuario (incluso de otras sesiones)
    )
    {:noreply, socket}
  end
  
  # Manejar versión antigua del mensaje (compatibilidad)
  @impl true
  def handle_info({:trip_completed, id, driver_name}, socket) do
    handle_info({:trip_completed, id, driver_name, 0, 0}, socket)
  end

  # El GenServer 'Trip' nos avisa que expiró
  @impl true
  def handle_info({:trip_expired, id}, socket) do
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()
    
    # Actualizar el puntaje
    new_score = case UrbanFleet.Server.my_score(username) do
      {:ok, s} -> s
      _ -> socket.assigns.score
    end
    
    # Recargar lista de viajes (usando función validada para evitar duplicados)
    # Esto incluye viajes de otras sesiones (filtrado por username, no por client_pid)
    client_trips = get_validated_client_trips(self(), username)
    
    # Buscar el siguiente viaje activo (pending o in_progress) después de expirar
    current_trip = Enum.find(client_trips, fn trip -> 
      trip.status == :pending || trip.status == :in_progress 
    end)
    current_trip_id = if current_trip, do: current_trip.id, else: nil
    
    socket = assign(socket, 
      status: "🔴 Tu viaje #{id} expiró sin conductor. ¡-5 puntos!",
      score: new_score,
      current_trip_id: current_trip_id,  # ⚠️ IMPORTANTE: Limpiar si no hay más viajes activos
      all_trips: client_trips  # Mostrar TODOS los viajes del usuario (incluso de otras sesiones)
    )
    {:noreply, socket}
  end
  
  # El GenServer 'Trip' nos avisa que fue cancelado
  @impl true
  def handle_info({:trip_cancelled, id, canceler_name, reason}, socket) do
    # Asegurar que el username esté normalizado
    username = socket.assigns.username |> String.trim() |> String.downcase()
    canceler_normalized = canceler_name |> String.trim() |> String.downcase()
    
    penalty_msg = if canceler_normalized == username, do: " (Penalización aplicada)", else: ""
    
    # Actualizar el puntaje en tiempo real si el cliente fue quien canceló
    new_score = if canceler_normalized == username do
      case UrbanFleet.Server.my_score(username) do
        {:ok, s} -> s
        _ -> socket.assigns.score
      end
    else
      socket.assigns.score
    end
    
    # Recargar lista de viajes (usando función validada para evitar duplicados)
    # Con manejo de errores por si algún proceso ya terminó
    client_trips = try do
      get_validated_client_trips(self(), username)
    rescue
      _ -> socket.assigns.all_trips || []
    catch
      _ -> socket.assigns.all_trips || []
    end
    
    # Verificar si el viaje ya existe en la lista antes de actualizar (evitar duplicados)
    # (Aunque get_validated_client_trips ya elimina duplicados, esto es una capa extra de seguridad)
    client_trips = client_trips |> Enum.uniq_by(& &1.id)
    
    # Buscar el siguiente viaje activo (pending o in_progress) después de la cancelación
    # Si el viaje cancelado era el current_trip_id, buscar el siguiente activo
    current_trip = if socket.assigns.current_trip_id == id do
      # El viaje cancelado era el actual, buscar el siguiente activo
      Enum.find(client_trips, fn trip -> 
        trip.status == :pending || trip.status == :in_progress 
      end)
    else
      # El viaje cancelado no era el actual, mantener el actual si sigue activo
      Enum.find(client_trips, fn trip -> 
        trip.id == socket.assigns.current_trip_id && 
        (trip.status == :pending || trip.status == :in_progress)
      end)
    end
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