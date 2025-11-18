defmodule UrbanFleetWebWeb.Validations do
  @moduledoc """
  Módulo de validaciones para formularios y datos de entrada
  """

  @doc """
  Valida el formulario de login
  Retorna {:ok, params} o {:error, changeset}
  """
  def validate_login(params) do
    errors = []

    errors =
      if blank?(params["username"]),
        do: [username: "El usuario es requerido"] ++ errors,
        else: errors

    errors =
      if blank?(params["password"]),
        do: [password: "La contraseña es requerida"] ++ errors,
        else: errors

    errors =
      if params["username"] && String.length(params["username"]) < 3,
        do: [username: "El usuario debe tener al menos 3 caracteres"] ++ errors,
        else: errors

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, errors}
    end
  end

  @doc """
  Valida el formulario de solicitud de viaje
  Retorna {:ok, params} o {:error, changeset}
  """
  def validate_trip_request(params) do
    errors = []

    origin = params["origin"]
    destination = params["destination"]

    errors =
      if blank?(origin),
        do: [origin: "El origen es requerido"] ++ errors,
        else: errors

    errors =
      if blank?(destination),
        do: [destination: "El destino es requerido"] ++ errors,
        else: errors

    errors =
      if origin == destination && !blank?(origin),
        do: [destination: "El origen y destino no pueden ser iguales"] ++ errors,
        else: errors

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, errors}
    end
  end

  @doc """
  Valida que una ubicación sea válida
  """
  def validate_location(location) do
    if blank?(location) do
      {:error, "La ubicación no puede estar vacía"}
    else
      if UrbanFleet.Location.is_valid?(location) do
        :ok
      else
        {:error, "La ubicación '#{location}' no es válida"}
      end
    end
  end

  @doc """
  Valida que el username tenga el formato correcto
  """
  def validate_username(username) do
    cond do
      blank?(username) ->
        {:error, "El usuario es requerido"}

      String.length(username) < 3 ->
        {:error, "El usuario debe tener al menos 3 caracteres"}

      String.length(username) > 50 ->
        {:error, "El usuario no puede tener más de 50 caracteres"}

      not Regex.match?(~r/^[a-zA-Z0-9_]+$/, username) ->
        {:error, "El usuario solo puede contener letras, números y guiones bajos"}

      true ->
        :ok
    end
  end

  @doc """
  Valida que la contraseña tenga el formato correcto
  """
  def validate_password(password) do
    cond do
      blank?(password) ->
        {:error, "La contraseña es requerida"}

      String.length(password) < 4 ->
        {:error, "La contraseña debe tener al menos 4 caracteres"}

      true ->
        :ok
    end
  end

  @doc """
  Valida que el origen y destino sean diferentes y válidos
  """
  def validate_origin_destination(origin, destination) do
    errors = []

    errors =
      if blank?(origin),
        do: [origin: "El origen es requerido"] ++ errors,
        else: errors

    errors =
      if blank?(destination),
        do: [destination: "El destino es requerido"] ++ errors,
        else: errors

    errors =
      if origin == destination && !blank?(origin),
        do: [destination: "El origen y destino no pueden ser iguales"] ++ errors,
        else: errors

    # Validar que las ubicaciones existan
    errors =
      if !blank?(origin) && not UrbanFleet.Location.is_valid?(origin),
        do: [origin: "La ubicación de origen no es válida"] ++ errors,
        else: errors

    errors =
      if !blank?(destination) && not UrbanFleet.Location.is_valid?(destination),
        do: [destination: "La ubicación de destino no es válida"] ++ errors,
        else: errors

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  @doc """
  Valida formato de razón de cancelación
  """
  def validate_cancellation_reason(reason) do
    cond do
      blank?(reason) ->
        {:error, "La razón de cancelación es requerida"}

      String.length(reason) < 3 ->
        {:error, "La razón debe tener al menos 3 caracteres"}

      String.length(reason) > 200 ->
        {:error, "La razón no puede tener más de 200 caracteres"}

      true ->
        :ok
    end
  end

  # Helper para verificar si un valor está vacío
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false
end

