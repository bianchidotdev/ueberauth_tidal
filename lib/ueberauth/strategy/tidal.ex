defmodule Ueberauth.Strategy.Tidal do
  @moduledoc """
  Tidal Strategy for Überauth.
  """

  use Ueberauth.Strategy,
    uid_field: :uid,
    default_scope: "user-read-email"

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Strategy.Helpers

  @doc """
  Handles initial redirect to the Tidal authentication page.

  To customize the scope (permissions) that are requested by Tidal include them as part of your url:

      "/auth/tidal?scope=user-read-email,user-read-privatet"

  You can also include a `state` param that Tidal will return to you.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    opts =
      [
        scope: scopes,
        state: Map.get(conn.params, "state", nil),
        show_dialog: Map.get(conn.params, "show_dialog", nil),
        redirect_uri: callback_url(conn)
      ]
      |> Helpers.with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Tidal.OAuth.authorize_url!(opts))
  end

  @doc """
  Handles the callback from Tidal. When there is a failure from Tidal the failure is included in the
  `ueberauth_failure` struct. Otherwise the information returned from Tidal is returned in the `Ueberauth.Auth` struct.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    options = [redirect_uri: callback_url(conn)]

    token = Ueberauth.Strategy.Tidal.OAuth.get_token!([code: code], options)

    if token.access_token == nil do
      set_errors!(conn, [
        error(
          token.other_params["error"],
          token.other_params["error_description"]
        )
      ])
    else
      fetch_user(conn, token)
    end
  end

  @doc """
  Handles the error callback from Tidal
  """
  def handle_callback!(%Plug.Conn{params: %{"error" => error}} = conn) do
    set_errors!(conn, [error("error", error)])
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :tidal_token, token)

    case Ueberauth.Strategy.Tidal.OAuth.get(token, "/me") do
      {:ok, %OAuth2.Response{status_code: 400, body: _body}} ->
        set_errors!(conn, [error("OAuth2", "400 - bad request")])

      {:ok, %OAuth2.Response{status_code: 404, body: _body}} ->
        set_errors!(conn, [error("OAuth2", "404 - not found")])

      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: status_code, body: user}}
      when status_code in 200..399 ->
        put_private(conn, :tidal_user, user)

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.tidal_user

    %Info{
      name: user["display_name"],
      nickname: user["id"],
      email: user["email"],
      image: List.first(user["images"])["url"],
      urls: %{external: user["external_urls"]["tidal"], tidal: user["uri"]},
      location: user["country"]
    }
  end

  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.tidal_token,
        user: conn.private.tidal_user
      }
    }
  end

  @doc """
  Includes the credentials from the Tidal response.
  """
  def credentials(conn) do
    token = conn.private.tidal_token
    scopes = token.other_params["scope"] || ""
    scopes = String.split(scopes, ",")

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: !!token.expires_at,
      scopes: scopes
    }
  end

  defp option(conn, key) do
    options(conn)
    |> Keyword.get(key, Keyword.get(default_options(), key))
  end
end
