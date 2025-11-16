defmodule UrbanFleet.Location do
  use Agent

  def start_link(_opts) do
    Agent.start_link(&init/0, name: __MODULE__)
  end

  def is_valid?(location_name) do
    locations = Agent.get(__MODULE__, &(&1))
    # Limpiar espacios en blanco y comparar
    cleaned_name = String.trim(location_name)
    Enum.any?(locations, fn loc -> String.trim(loc) == cleaned_name end)
  end

  def all, do: Agent.get(__MODULE__, &(&1))
  
  # Función de debug para verificar qué ubicaciones están cargadas
  def debug_info do
    locations = Agent.get(__MODULE__, &(&1))
    IO.puts("Ubicaciones cargadas (#{length(locations)}):")
    Enum.each(locations, fn loc -> IO.puts("  '#{loc}' (longitud: #{String.length(loc)})") end)
    locations
  end

  defp get_locations_file do
    # Intenta varias rutas posibles
    cwd = File.cwd!()
    base_paths = [
      Path.join([cwd, "lib", "data", "locations.dat"]),  # Ruta absoluta desde cwd
      Path.join([__DIR__, "..", "..", "data", "locations.dat"]),  # Relativa al archivo fuente
      "lib/data/locations.dat"  # Desde el directorio raíz del proyecto
    ]
    
    Enum.find_value(base_paths, fn path ->
      normalized = Path.expand(path)
      if File.exists?(normalized), do: normalized, else: nil
    end) || Path.join([cwd, "lib", "data", "locations.dat"])
  end

  defp init do
    file_path = get_locations_file()
    
    file_path
    |> File.read()
    |> case do
      {:ok, content} ->
        locations = content
        |> String.split("\n", trim: true)
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&String.trim/1)  # Limpiar espacios en blanco adicionales
        
        if Enum.empty?(locations) do
          IO.puts("Advertencia: locations.dat está vacío.")
        else
          IO.puts("✅ Cargadas #{length(locations)} ubicaciones desde #{file_path}")
        end
        
        locations

      {:error, reason} ->
        IO.puts("Advertencia: No se pudo cargar locations.dat desde #{file_path}: #{inspect(reason)}")
        IO.puts("Directorio actual: #{File.cwd!()}")
        []
    end
  end
end