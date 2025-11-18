defmodule UrbanFleetWebWeb.ValidationsTest do
  use ExUnit.Case, async: true

  alias UrbanFleetWebWeb.Validations

  describe "validate_login/1" do
    test "acepta credenciales válidas" do
      params = %{"username" => "ana", "password" => "pass123"}
      assert {:ok, _} = Validations.validate_login(params)
    end

    test "rechaza username vacío" do
      params = %{"username" => "", "password" => "pass123"}
      assert {:error, errors} = Validations.validate_login(params)
      assert Keyword.has_key?(errors, :username)
    end

    test "rechaza password vacío" do
      params = %{"username" => "ana", "password" => ""}
      assert {:error, errors} = Validations.validate_login(params)
      assert Keyword.has_key?(errors, :password)
    end

    test "rechaza username muy corto" do
      params = %{"username" => "ab", "password" => "pass123"}
      assert {:error, errors} = Validations.validate_login(params)
      assert Keyword.has_key?(errors, :username)
    end
  end

  describe "validate_trip_request/1" do
    test "acepta origen y destino válidos y diferentes" do
      params = %{"origin" => "Centro", "destination" => "Norte"}
      assert {:ok, _} = Validations.validate_trip_request(params)
    end

    test "rechaza origen vacío" do
      params = %{"origin" => "", "destination" => "Norte"}
      assert {:error, errors} = Validations.validate_trip_request(params)
      assert Keyword.has_key?(errors, :origin)
    end

    test "rechaza destino vacío" do
      params = %{"origin" => "Centro", "destination" => ""}
      assert {:error, errors} = Validations.validate_trip_request(params)
      assert Keyword.has_key?(errors, :destination)
    end

    test "rechaza origen y destino iguales" do
      params = %{"origin" => "Centro", "destination" => "Centro"}
      assert {:error, errors} = Validations.validate_trip_request(params)
      assert Keyword.has_key?(errors, :destination)
    end
  end

  describe "validate_username/1" do
    test "acepta username válido" do
      assert :ok = Validations.validate_username("ana")
      assert :ok = Validations.validate_username("driver_luis")
      assert :ok = Validations.validate_username("user123")
    end

    test "rechaza username vacío" do
      assert {:error, _} = Validations.validate_username("")
      assert {:error, _} = Validations.validate_username(nil)
    end

    test "rechaza username muy corto" do
      assert {:error, _} = Validations.validate_username("ab")
    end

    test "rechaza username muy largo" do
      long_username = String.duplicate("a", 51)
      assert {:error, _} = Validations.validate_username(long_username)
    end

    test "rechaza username con caracteres especiales inválidos" do
      assert {:error, _} = Validations.validate_username("user@name")
      assert {:error, _} = Validations.validate_username("user-name")
      assert {:error, _} = Validations.validate_username("user name")
    end
  end

  describe "validate_password/1" do
    test "acepta password válido" do
      assert :ok = Validations.validate_password("pass123")
      assert :ok = Validations.validate_password("mypassword")
    end

    test "rechaza password vacío" do
      assert {:error, _} = Validations.validate_password("")
      assert {:error, _} = Validations.validate_password(nil)
    end

    test "rechaza password muy corto" do
      assert {:error, _} = Validations.validate_password("abc")
    end
  end
end

