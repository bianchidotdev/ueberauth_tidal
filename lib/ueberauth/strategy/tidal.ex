defmodule Ueberauth.Strategy.Tidal do
  @moduledoc """
  Tidal Strategy for Überauth.
  """

  use Ueberauth.Strategy,
    uid_field: :uid,
    default_scope: "user.read"

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra
  alias Ueberauth.Strategy.Helpers

  @code_verifier_cookie "ueberauth.tidal_code_verifier"

  @doc """
  Handles initial redirect to the Tidal authentication page.

  To customize the scope (permissions) that are requested by Tidal include them as part of your url:

      "/authorize
        ?response_type=code
        &client_id=<CLIENT_ID>
        &redirect_uri=<REDIRECT_URI>
        &scope=<SCOPES>
        &code_challenge_method=S256
        &code_challenge=<CODE_CHALLENGE>
        &state=<STATE>

  You can also include a `state` param that Tidal will return to you.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    code_verifier = UeberauthTidal.Challenge.generate_code_verifier()

    params =
      [
        response_type: "code",
        scope: scopes,
        redirect_uri: callback_url(conn)
      ]
      |> put_client_id()
      |> put_code_challenge(code_verifier)
      |> Helpers.with_state_param(conn)

    conn
    |> put_resp_cookie(@code_verifier_cookie, code_verifier, same_site: "Lax")
    |> redirect!(Ueberauth.Strategy.Tidal.OAuth.authorize_url!(params))
  end

  defp put_client_id(params) do
    %{client_id: client_id} = get_credentials()

    Keyword.put(params, :client_id, client_id)
  end

  defp get_credentials() do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Tidal.OAuth)

    %{
      client_id: config[:client_id],
      client_secret: config[:client_secret]
    }
  end

  defp put_code_challenge(opts, code_verifier) do
    %{
      code_challenge: code_challenge,
      code_challenge_method: code_challenge_method
    } = UeberauthTidal.Challenge.get_code_challenge(code_verifier)

    opts
    |> Keyword.put(:code_challenge, code_challenge)
    |> Keyword.put(:code_challenge_method, code_challenge_method)
  end

  @doc """
  Handles the callback from Tidal. When there is a failure from Tidal the failure is included in the
  `ueberauth_failure` struct. Otherwise the information returned from Tidal is returned in the `Ueberauth.Auth` struct.
  """
  def handle_callback!(
        %Plug.Conn{
          params: %{"code" => code, "state" => state},
          req_cookies: %{"ueberauth.state_param" => state}
        } = conn
      )
      when is_binary(code) do
    params =
      [
        grant_type: "authorization_code",
        code: code,
        redirect_uri: callback_url(conn),
        code_verifier: fetch_code_verifier!(conn)
      ]
      |> put_client_id()

    token = Ueberauth.Strategy.Tidal.OAuth.get_token!(params)

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

  # @doc """
  # Handles the error callback from Tidal
  # """
  def handle_callback!(%Plug.Conn{params: %{"error" => error}} = conn) do
    set_errors!(conn, [error("error", error)])
  end

  def handle_callback!(
        %Plug.Conn{
          params: %{
            "code" => code
          }
        } = conn
      )
      when not is_binary(code) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  defp fetch_code_verifier!(conn) do
    code_verifier =
      conn
      |> fetch_session()
      |> Map.get(:cookies)
      |> Map.get(@code_verifier_cookie)

    case code_verifier do
      nil -> raise "could not fetch the code verifier"
      code_verifier -> code_verifier
    end
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :tidal_token, token)

    case Ueberauth.Strategy.Tidal.OAuth.get(token, "/users/me",
           accept: "application/vnd.api+json"
         ) do
      {:ok, %OAuth2.Response{status_code: 400, body: _body}} ->
        set_errors!(conn, [error("OAuth2", "400 - bad request")])

      {:ok, %OAuth2.Response{status_code: 404, body: _body}} ->
        set_errors!(conn, [error("OAuth2", "404 - not found")])

      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      # because tidal uses a funky specific header for json api,
      # we don't get automatic json parsing through ueberauth
      # We check to see if the response is a binary, and then we
      # try to parse it. That's why we currently require the Jason
      # library. There's probably a solid way around this
      {:ok, %OAuth2.Response{status_code: status_code, body: user}}
      when status_code in 200..399 ->
        case user do
          %{"data" => user} ->
            put_private(conn, :tidal_user, user)

          %{} ->
            set_errors!(conn, [error("OAuth2", "user not found")])

          json_string when is_binary(json_string) ->
            Jason.decode(json_string)
            |> case do
              {:ok, parsed} ->
                put_private(conn, :tidal_user, parsed["data"])

              _ ->
                set_errors!(conn, [error("OAuth2", "user not found")])
            end

          _ ->
            set_errors!(conn, [error("OAuth2", "user not found")])
        end

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
      name: get_in(user, ["attributes", "username"]),
      nickname: user["id"],
      email: get_in(user, ["attributes", "email"]),
      # image: List.first(user["images"])["url"],
      # urls: %{external: user["external_urls"]["tidal"], tidal: user["uri"]},
      location: get_in(user, ["attributes", "country"])
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
