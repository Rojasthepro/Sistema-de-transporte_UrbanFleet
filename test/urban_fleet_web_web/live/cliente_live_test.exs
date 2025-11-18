defmodule UrbanFleetWebWeb.ClienteLiveTest do
  use UrbanFleetWebWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Cliente LiveView" do
    test "redirige al login si no hay usuario autenticado", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/cliente")
    end

    test "renderiza el panel del cliente cuando hay usuario autenticado", %{conn: conn} do
      # Simular usuario autenticado pasando el parámetro user
      {:ok, view, html} = live(conn, ~p"/cliente?user=ana")

      assert html =~ "Panel del Cliente"
      assert html =~ "ana"
      assert has_element?(view, "form#trip-form")
      assert has_element?(view, "select[name='trip[origin]']")
      assert has_element?(view, "select[name='trip[destination]']")
    end

    test "muestra el puntaje del usuario", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/cliente?user=ana")

      # Verificar que se muestra el puntaje (puede ser 0 si es nuevo)
      assert html =~ "Puntos"
    end

    test "valida que origen y destino no sean iguales", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cliente?user=ana")

      html =
        view
        |> form("#trip-form", trip: %{origin: "Centro", destination: "Centro"})
        |> render_submit()

      assert html =~ "origen y destino no pueden ser iguales"
    end

    test "solicita un viaje cuando los datos son válidos", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cliente?user=ana")

      # Asegúrate de que "Centro" y "Norte" existan en locations.dat
      html =
        view
        |> form("#trip-form", trip: %{origin: "Centro", destination: "Norte"})
        |> render_submit()

      # Verificar que se muestra mensaje de éxito o que el viaje fue solicitado
      assert html =~ "solicitado" || html =~ "Buscando conductor"
    end

    test "muestra error cuando la ubicación es inválida", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cliente?user=ana")

      html =
        view
        |> form("#trip-form", trip: %{origin: "UbicacionInexistente", destination: "OtraInexistente"})
        |> render_submit()

      assert html =~ "inválida" || html =~ "Error"
    end

    test "muestra notificación cuando un viaje es aceptado", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cliente?user=ana")

      # Simular notificación del GenServer
      send(view.pid, {:trip_accepted, "driver_luis"})

      assert render(view) =~ "Aceptado"
    end

    test "actualiza el puntaje cuando un viaje se completa", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/cliente?user=ana")

      # Simular notificación de viaje completado
      send(view.pid, {:trip_completed, 123, "driver_luis"})

      html = render(view)
      assert html =~ "completado" || html =~ "puntos"
    end
  end
end

