defmodule UrbanFleetWebWeb.LiveViewCase do
  @moduledoc """
  Helper para tests de LiveView
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with LiveView
      import Phoenix.LiveViewTest
      import UrbanFleetWebWeb.ConnCase
    end
  end

  setup tags do
    # Configurar datos de prueba si es necesario
    # Por ejemplo, crear usuarios de prueba, ubicaciones, etc.

    :ok
  end
end

