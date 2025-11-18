defmodule UrbanFleetWebWeb.UserAuth do
  @moduledoc """
  Hook para manejar autenticación en LiveView
  """
  import Phoenix.Component

  def on_mount(:mount_current_user, _params, session, socket) do
    username = Map.get(session, "username")
    role = Map.get(session, "role")
    {:cont, assign(socket, current_user: username, user_role: role)}
  end
end

