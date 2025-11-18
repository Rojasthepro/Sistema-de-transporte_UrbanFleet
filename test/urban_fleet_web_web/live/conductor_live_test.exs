defmodule UrbanFleetWebWeb.ConductorLiveTest do
  use UrbanFleetWebWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Conductor LiveView" do
    test "redirige al login si no hay usuario autenticado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/conductor")
    end

    test "renderiza el panel del conductor cuando hay usuario autenticado", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/conductor?user=driver_luis")

      assert html =~ "Panel del Conductor"
      assert html =~ "driver_luis"
      assert has_element?(view, "button", "Aceptar")
    end

    test "muestra la lista de viajes disponibles", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/conductor?user=driver_luis")

      # Verificar que se muestra la sección de viajes
      assert html =~ "Viajes Disponibles"
    end

    test "acepta un viaje cuando se hace clic en el botón", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/conductor?user=driver_luis")

      # Primero necesitas tener un viaje disponible en el sistema
      # Este test requiere que haya un viaje pendiente

      # Simular clic en aceptar viaje (ajusta el trip-id según tus datos)
      html =
        view
        |> element("button[phx-click='accept_trip']")
        |> render_click()

      # Verificar que se muestra mensaje de éxito o que el viaje fue aceptado
      assert html =~ "aceptado" || html =~ "En progreso"
    end

    test "muestra notificación cuando hay un nuevo viaje disponible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/conductor?user=driver_luis")

      # Simular notificación de nuevo viaje
      trip = %{id: 999, origin: "Centro", destination: "Norte", client_name: "ana"}
      send(view.pid, {:new_trip_available, trip})

      html = render(view)
      assert html =~ "NUEVO VIAJE" || html =~ "999"
    end

    test "actualiza el puntaje cuando se completa un viaje", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/conductor?user=driver_luis")

      # Simular notificación de viaje completado
      send(view.pid, {:trip_completed, 123, "ana"})

      html = render(view)
      assert html =~ "completado" || html =~ "puntos"
    end

    test "se desconecta correctamente", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/conductor?user=driver_luis")

      view
      |> element("button[phx-click='disconnect']")
      |> render_click()

      assert_redirect(view, ~p"/login")
    end
  end
end

