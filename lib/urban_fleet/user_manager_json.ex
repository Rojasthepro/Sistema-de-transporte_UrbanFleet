defmodule UrbanFleet.UserManagerJSON do
  @moduledoc """
  Módulo opcional para persistencia en formato JSON
  Mantiene compatibilidad con el formato .dat existente
  """
  use GenServer

  @users_json_file "lib/data/users.json"
  @users_dat_file "lib/data/user.dat"

  defstruct file_path_json: nil, file_path_dat: nil, users: %{}

  # --- API Pública ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, {@users_json_file, @users_dat_file}, name: __MODULE__)
  end

  @doc "Exporta usuarios a JSON"
  def export_to_json do
    GenServer.call(__MODULE__, :export_to_json)
  end

  @doc "Importa usuarios desde JSON"
  def import_from_json do
    GenServer.call(__MODULE__, :import_from_json)
  end

  # --- Callbacks GenServer ---
  @impl true
  def init({json_path, dat_path}) do
    # Cargar desde .dat primero (compatibilidad)
    users = load_from_dat(dat_path)
    {:ok, %__MODULE__{file_path_json: json_path, file_path_dat: dat_path, users: users}}
  end

  @impl true
  def handle_call(:export_to_json, _from, state) do
    json_data = %{
      users: Enum.map(state.users, fn {_username, user} ->
        %{
          username: user.username,
          role: user.role,
          password: user.password,
          score: user.score
        }
      end)
    }

    # Usar :erlang.term_to_binary para simplicidad (o agregar Jason como dependencia)
    # Por ahora, usamos un formato simple
    json_string = format_json_simple(json_data)
    File.write(state.file_path_json, json_string)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:import_from_json, _from, state) do
    users = load_from_json(state.file_path_json)
    {:reply, :ok, %{state | users: users}}
  end

  # --- Funciones Privadas ---
  defp load_from_dat(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.filter(&(&1 != "" and not String.starts_with?(&1, "#")))
        |> Enum.map(&parse_user_line/1)
        |> Enum.into(%{})

      {:error, _} ->
        %{}
    end
  end

  defp load_from_json(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        parse_json_simple(content)

      {:error, _} ->
        %{}
    end
  end

  defp parse_user_line(line) do
    try do
      [username, role, password, score_str] = String.split(line, ",", parts: 4)
      {score, _} = Integer.parse(score_str)
      {username, %{username: username, role: role, password: password, score: score}}
    rescue
      _ -> nil
    end
  end

  # Formato JSON simple sin dependencias externas
  defp format_json_simple(data) do
    users_json = Enum.map(data.users, fn user ->
      """
        {
          "username": "#{user.username}",
          "role": "#{user.role}",
          "password": "#{user.password}",
          "score": #{user.score}
        }
      """
    end)
    |> Enum.join(",\n")

    """
    {
      "users": [
#{users_json}
      ]
    }
    """
  end

  defp parse_json_simple(_content) do
    # Parsing simple de JSON (básico, para producción usar Jason)
    # Por ahora retornamos vacío y se puede mejorar después
    %{}
  end
end

