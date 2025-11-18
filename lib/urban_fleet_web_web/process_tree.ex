defmodule UrbanFleetWebWeb.ProcessTree do
  @moduledoc """
  Módulo helper para visualizar el árbol de procesos de UrbanFleet
  """
  
  def show do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("🌳 ÁRBOL DE PROCESOS URBANFLEET")
    IO.puts(String.duplicate("=", 60) <> "\n")
    
    # Supervisor de Phoenix Web (contiene todos los procesos)
    show_supervisor(UrbanFleetWeb.Supervisor, "UrbanFleet Web Supervisor")
    
    # Procesos individuales importantes
    IO.puts("\n📦 PROCESOS PRINCIPALES:")
    IO.puts(String.duplicate("-", 60))
    show_process(UrbanFleet.UserManager, "UserManager")
    show_process(UrbanFleet.DriverStats, "DriverStats")
    show_process(UrbanFleet.TripLogger, "TripLogger")
    show_process(UrbanFleet.Location, "Location")
    show_process(UrbanFleet.UserManagerJSON, "UserManagerJSON")
    
    # Viajes activos
    show_active_trips()
    
    # Conductores online
    show_online_drivers()
    
    IO.puts("\n" <> String.duplicate("=", 60) <> "\n")
  end
  
  defp show_supervisor(name, label) do
    case Process.whereis(name) do
      nil -> 
        IO.puts("❌ #{label}: No iniciado")
      pid -> 
        IO.puts("\n✅ #{label} (#{inspect(pid)}):")
        IO.puts(String.duplicate("-", 60))
        try do
          children = Supervisor.which_children(name)
          if Enum.empty?(children) do
            IO.puts("  (Sin hijos)")
          else
            Enum.each(children, fn {id, child, type, modules} ->
              status = if is_pid(child) and Process.alive?(child), do: "✅", else: "❌"
              child_str = if is_pid(child), do: inspect(child), else: inspect(child)
              module_name = get_module_name(id, child)
              IO.puts("  #{status} #{module_name}")
              IO.puts("     ID: #{inspect(id)}")
              IO.puts("     PID: #{child_str}")
              IO.puts("     Tipo: #{type}")
              if modules != :undefined and modules != [] do
                IO.puts("     Módulos: #{inspect(modules)}")
              end
            end)
          end
        rescue
          e -> IO.puts("  Error: #{inspect(e)}")
        end
    end
  end
  
  defp get_module_name(id, _child) when is_atom(id), do: inspect(id)
  defp get_module_name(id, child) when is_pid(child) do
    # Intentar obtener el nombre del módulo desde el proceso
    try do
      case Process.info(child, [:registered_name]) do
        [registered_name: name] when is_atom(name) -> inspect(name)
        _ -> inspect(id)
      end
    rescue
      _ -> inspect(id)
    end
  end
  defp get_module_name(id, _), do: inspect(id)
  
  defp show_process(name, label) do
    case Process.whereis(name) do
      nil -> 
        IO.puts("❌ #{label}: No iniciado")
      pid -> 
        try do
          info = Process.info(pid, [:memory, :message_queue_len, :current_function])
          memory = info[:memory] || 0
          queue = info[:message_queue_len] || 0
          func = info[:current_function] || :unknown
          status = if Process.alive?(pid), do: "✅", else: "❌"
          IO.puts("#{status} #{label}")
          IO.puts("   PID: #{inspect(pid)}")
          IO.puts("   Memoria: #{format_bytes(memory)}")
          IO.puts("   Cola de mensajes: #{queue}")
          IO.puts("   Función actual: #{inspect(func)}")
        rescue
          _ -> IO.puts("✅ #{label}: #{inspect(pid)} (sin info)")
        end
    end
  end
  
  defp show_active_trips do
    try do
      trips = Registry.select(Registry.UrbanFleet, [
        {{:"$1", :"$2", :"$3"}, 
         [{:is_binary, :"$1"}], 
         [{{:"$1", :"$2", :"$3"}}]}
      ])
      |> Enum.filter(fn {key, _, _} -> 
        key_str = to_string(key)
        String.starts_with?(key_str, "trip_")
      end)
      
      IO.puts("\n🚗 VIAJES ACTIVOS: #{length(trips)}")
      IO.puts(String.duplicate("-", 60))
      
      if Enum.empty?(trips) do
        IO.puts("  (No hay viajes activos)")
      else
        Enum.each(trips, fn {key, _value, pid} ->
          status = if Process.alive?(pid), do: "✅", else: "❌"
          IO.puts("#{status} #{key}")
          IO.puts("   PID: #{inspect(pid)}")
          
          # Intentar obtener información del viaje
          try do
            case GenServer.call(pid, :get_status, 1000) do
              {:ok, trip_info} ->
                IO.puts("   Origen: #{trip_info.origin}")
                IO.puts("   Destino: #{trip_info.destination}")
                IO.puts("   Estado: #{trip_info.status}")
              _ -> :ok
            end
          rescue
            _ -> :ok
          end
        end)
      end
    rescue
      e -> IO.puts("  Error al obtener viajes: #{inspect(e)}")
    end
  end
  
  defp show_online_drivers do
    try do
      drivers = Registry.lookup(Registry.UrbanFleet, :drivers_online)
      
      IO.puts("\n👨‍✈️ CONDUCTORES ONLINE: #{length(drivers)}")
      IO.puts(String.duplicate("-", 60))
      
      if Enum.empty?(drivers) do
        IO.puts("  (No hay conductores online)")
      else
        Enum.each(drivers, fn {pid, _value} ->
          status = if Process.alive?(pid), do: "✅", else: "❌"
          IO.puts("#{status} Conductor")
          IO.puts("   PID: #{inspect(pid)}")
        end)
      end
    rescue
      e -> IO.puts("  Error al obtener conductores: #{inspect(e)}")
    end
  end
  
  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000 -> "#{:erlang.float_to_binary(bytes / 1_000_000, decimals: 2)} MB"
      bytes >= 1_000 -> "#{:erlang.float_to_binary(bytes / 1_000, decimals: 2)} KB"
      true -> "#{bytes} bytes"
    end
  end
  defp format_bytes(_), do: "N/A"
end

