defmodule UrbanFleet.UserManager do
  use GenServer

  @users_file "lib/urban_fleet/data/users.json"

  defstruct file_path: nil, users: %{}

  # --- API Pública ---
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, @users_file, name: __MODULE__)
  end

  def connect(username, password) do
    GenServer.call(__MODULE__, {:connect, username, password})
  end

  def get_score(username) do
    GenServer.call(__MODULE__, {:get_score, username})
  end

  def update_score(username, points_to_add) do
    GenServer.cast(__MODULE__, {:update_score, username, points_to_add})
  end

  def get_rankings do
    GenServer.call(__MODULE__, :get_rankings)
  end

  # --- Callbacks GenServer ---
  @impl true
  def init(file_path) do
    users = load_users_from_file(file_path)
    {:ok, %__MODULE__{file_path: file_path, users: users}}
  end

  @impl true
  def handle_call({:connect, username, password}, _from, state) do
    user = Map.get(state.users, username)

    reply =
      case user do
        %{password: stored_pass} = existing_user ->
          if stored_pass == password,
            do: {:ok, :login, existing_user.role},
            else: {:error, :wrong_password}

        nil ->
          role = if String.starts_with?(username, "driver_"), do: "conductor", else: "cliente"
          new_user = %{username: username, role: role, password: password, score: 0}
          # Persistir en archivo
          persist_user(state.file_path, new_user)
          # Actualizar estado en memoria
          updated_users = Map.put(state.users, username, new_user)
          {:reply, {:ok, :registered, role}, %{state | users: updated_users}}
      end

    if elem(reply, 0) == :reply, do: reply, else: {:reply, reply, state}
  end

  @impl true
  def handle_call({:get_score, username}, _from, state) do
    user = Map.get(state.users, username)
    reply = if user, do: {:ok, user.score}, else: {:error, :not_found}
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:get_rankings, _from, state) do
    all_users = Map.values(state.users)
    {clients, drivers} = Enum.split_with(all_users, &(&1.role == "cliente"))
    sort_fn = fn userA, userB -> userA.score >= userB.score end

    rankings = %{
      clients: Enum.sort(clients, sort_fn) |> Enum.take(10),
      drivers: Enum.sort(drivers, sort_fn) |> Enum.take(10)
    }
    {:reply, {:ok, rankings}, state}
  end

  @impl true
  def handle_cast({:update_score, username, points_to_add}, state) do
    if user = Map.get(state.users, username) do
      updated_user = %{user | score: user.score + points_to_add}
      updated_users = Map.put(state.users, username, updated_user)
      # Re-escribir todo el archivo (más seguro para este formato)
      write_all_users(state.file_path, updated_users)
      {:noreply, %{state | users: updated_users}}
    else
      {:noreply, state}
    end
  end

  # --- Funciones Privadas ---
  defp load_users_from_file(file_path) do
    file_path
    |> File.read()
    |> case do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"users" => users_list}} ->
            users_list
            |> Enum.map(fn user_data ->
              username = Map.get(user_data, "username")
              user = %{
                username: username,
                role: Map.get(user_data, "role"),
                password: Map.get(user_data, "password"),
                score: Map.get(user_data, "score", 0)
              }
              {username, user}
            end)
            |> Enum.into(%{})

          {:ok, _} ->
            # Formato JSON inválido o estructura diferente
            %{}

          {:error, _} ->
            # Si falla el parseo JSON, intentar migrar desde .dat si existe
            migrate_from_dat(file_path)
        end

      {:error, _} ->
        # Si no existe el archivo JSON, intentar migrar desde .dat si existe
        migrate_from_dat(file_path)
    end
  end

  # Migración automática desde .dat a JSON (solo una vez)
  defp migrate_from_dat(json_path) do
    dat_path = String.replace(json_path, "users.json", "user.dat")
    
    case File.read(dat_path) do
      {:ok, content} ->
        users = content
        |> String.split("\n", trim: true)
        |> Enum.filter(&(&1 != "" and not String.starts_with?(&1, "#")))
        |> Enum.map(&parse_user_line_dat/1)
        |> Enum.filter(&(&1 != nil))
        |> Enum.into(%{})
        
        # Guardar en formato JSON
        if map_size(users) > 0 do
          write_all_users(json_path, users)
        end
        
        users

      {:error, _} ->
        # No existe .dat, empezar con JSON vacío
        %{}
    end
  end

  defp parse_user_line_dat(line) do
    try do
      [username, role, password, score_str] = String.split(line, ",", parts: 4)
      {score, _} = Integer.parse(score_str)
      {username, %{username: username, role: role, password: password, score: score}}
    rescue
      _ -> nil
    end
  end

  defp persist_user(file_path, user) do
    # Cargar usuarios existentes
    existing_users = load_users_from_file(file_path)
    
    # Agregar nuevo usuario
    updated_users = Map.put(existing_users, user.username, user)
    
    # Guardar todo en JSON
    write_all_users(file_path, updated_users)
  end

  defp write_all_users(file_path, users_map) do
    users_list =
      users_map
      |> Map.values()
      |> Enum.map(fn user ->
        %{
          username: user.username,
          role: user.role,
          password: user.password,
          score: user.score
        }
      end)

    json_data = %{users: users_list}
    
    case Jason.encode(json_data, pretty: true) do
      {:ok, json_string} ->
        File.write(file_path, json_string)
      {:error, _} ->
        # Fallback: escribir sin pretty print
        case Jason.encode(json_data) do
          {:ok, json_string} -> File.write(file_path, json_string)
          {:error, _} -> :error
        end
    end
  end
end