defmodule UrbanFleetWebWeb.LoginLive do
  use UrbanFleetWebWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    form = to_form(%{}, as: :user)
    {:ok, assign(socket, form: form, error: nil)}
  end

  @impl true
  def handle_event("connect", %{"user" => %{"username" => username, "password" => password}}, socket) do
    case UrbanFleet.Server.connect(username, password) do
      {:ok, _type, role} ->
        # Redirigir según el rol con username en la URL (la sesión se maneja en el hook UserAuth)
        base_path = if role == "conductor", do: "/conductor", else: "/cliente"
        redirect_path = "#{base_path}?user=#{URI.encode(username)}"
        
        socket = 
          socket
          |> put_flash(:info, "✅ #{if role == "conductor", do: "Conductor", else: "Cliente"} conectado exitosamente")
          |> push_navigate(to: redirect_path)
        
        {:noreply, socket}

      {:error, reason} ->
        error_msg = case reason do
          :wrong_password -> "❌ Contraseña incorrecta"
          _ -> "❌ Error: #{reason}"
        end
        
        socket = assign(socket, error: error_msg)
        {:noreply, socket}
    end
  end
end

