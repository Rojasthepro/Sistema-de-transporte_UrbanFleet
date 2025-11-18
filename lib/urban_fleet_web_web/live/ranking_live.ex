defmodule UrbanFleetWebWeb.RankingLive do
  use UrbanFleetWebWeb, :live_view

  @impl true
  def mount(params, session, socket) do
    # Obtener username y rol de los parámetros de la URL, sesión o assigns
    username = Map.get(params, "user") || Map.get(session, "username") || socket.assigns[:current_user]
    role = Map.get(session, "role") || socket.assigns[:user_role]
    
    # Si tenemos username pero no rol, determinar por el nombre (convención: driver_ = conductor)
    role = if username && is_nil(role) do
      if String.starts_with?(username, "driver_"), do: "conductor", else: "cliente"
    else
      role
    end
    
    case UrbanFleet.Server.show_ranking() do
      {:ok, rankings} ->
        socket = assign(socket, 
          clients: Map.get(rankings, :clients, []),
          drivers: Map.get(rankings, :drivers, []),
          current_user: username,
          user_role: role
        )
        {:ok, socket}
      
      {:error, _reason} ->
        socket = assign(socket, 
          clients: [], 
          drivers: [],
          current_user: username,
          user_role: role
        )
        {:ok, socket}
    end
  end
end

