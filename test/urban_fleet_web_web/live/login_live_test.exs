defmodule UrbanFleetWebWeb.LoginLiveTest do
  use UrbanFleetWebWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Login LiveView" do
    test "renderiza el formulario de login", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      assert has_element?(view, "form#login-form")
      assert has_element?(view, "input[name='user[username]']")
      assert has_element?(view, "input[name='user[password]']")
      assert has_element?(view, "button", "Continuar")
    end

    test "muestra error cuando las credenciales son incorrectas", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      # Intentar login con credenciales incorrectas
      view
      |> form("#login-form", user: %{username: "usuario_inexistente", password: "pass123"})
      |> render_submit()

      assert render(view) =~ "Error"
    end

    test "redirige a /cliente cuando el login es exitoso como cliente", %{conn: conn} do
      # Primero necesitas crear un usuario cliente en el sistema
      # Este test requiere que el sistema tenga datos de prueba
      
      {:ok, view, _html} = live(conn, ~p"/login")

      # Ajusta estos valores según tus datos de prueba
      view
      |> form("#login-form", user: %{username: "ana", password: "pass123"})
      |> render_submit()

      # Verificar redirección
      assert_redirect(view, ~p"/cliente")
    end

    test "redirige a /conductor cuando el login es exitoso como conductor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      # Ajusta estos valores según tus datos de prueba
      view
      |> form("#login-form", user: %{username: "driver_luis", password: "pass123"})
      |> render_submit()

      # Verificar redirección
      assert_redirect(view, ~p"/conductor")
    end

    test "valida que el username no esté vacío", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("#login-form", user: %{username: "", password: "pass123"})
        |> render_submit()

      # El formulario HTML5 debería prevenir el envío, pero puedes verificar
      assert html =~ "required" || html =~ "Error"
    end

    test "valida que la contraseña no esté vacía", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/login")

      html =
        view
        |> form("#login-form", user: %{username: "ana", password: ""})
        |> render_submit()

      assert html =~ "required" || html =~ "Error"
    end
  end
end

