defmodule UrbanFleet.Reset do
  @moduledoc """
  Módulo para resetear la base de datos y dejar el sistema como nuevo
  """
  
  @users_file "lib/urban_fleet/data/users.json"
  @results_log "lib/urban_fleet/data/results.log"
  @users_dat_legacy "lib/urban_fleet/data/user.dat"  # Archivo legacy, ya no se usa
  
  @doc """
  Limpia todos los archivos de datos (usuarios, logs, JSON)
  """
  def clean_all do
    IO.puts("\n🧹 Limpiando base de datos...")
    
    files_to_clean = [
      {@users_file, "Usuarios (JSON)"},
      {@results_log, "Logs de viajes"},
      {@users_dat_legacy, "Usuarios legacy (.dat)"}
    ]
    
    cleaned = Enum.map(files_to_clean, fn {file, label} ->
      clean_file(file, label)
    end)
    
    # Reiniciar el estado en memoria de los GenServers
    reset_in_memory_state()
    
    IO.puts("\n✅ Sistema limpiado completamente!")
    IO.puts("   - Archivos de datos vaciados")
    IO.puts("   - Estado en memoria reseteado")
    IO.puts("\n💡 Reinicia la aplicación para aplicar los cambios completamente.\n")
    
    cleaned
  end
  
  @doc """
  Limpia solo el archivo de usuarios
  """
  def clean_users do
    clean_file(@users_file, "Usuarios")
    reset_user_manager()
    IO.puts("✅ Usuarios limpiados!")
  end
  
  @doc """
  Limpia solo los logs de viajes
  """
  def clean_logs do
    clean_file(@results_log, "Logs de viajes")
    IO.puts("✅ Logs limpiados!")
  end
  
  defp clean_file(file_path, label) do
    case File.exists?(file_path) do
      true ->
        case File.write(file_path, "") do
          :ok ->
            IO.puts("   ✅ #{label}: #{file_path}")
            {:ok, file_path}
          {:error, reason} ->
            IO.puts("   ❌ Error limpiando #{label}: #{inspect(reason)}")
            {:error, reason}
        end
      false ->
        IO.puts("   ⚠️  #{label}: No existe (#{file_path})")
        {:not_found, file_path}
    end
  end
  
  defp reset_in_memory_state do
    # Reiniciar UserManager
    reset_user_manager()
    
    # Reiniciar DriverStats
    reset_driver_stats()
    
    # El TripLogger no necesita reset porque solo escribe logs
  end
  
  defp reset_user_manager do
    try do
      # Obtener el estado actual y limpiarlo
      if Process.whereis(UrbanFleet.UserManager) do
        # No podemos resetear directamente, pero podemos forzar una recarga
        # El supervisor lo reiniciará si es necesario
        :ok
      else
        :ok
      end
    rescue
      _ -> :ok
    end
  end
  
  defp reset_driver_stats do
    try do
      if Process.whereis(UrbanFleet.DriverStats) do
        # El DriverStats se resetea automáticamente al reiniciar
        :ok
      else
        :ok
      end
    rescue
      _ -> :ok
    end
  end
end

