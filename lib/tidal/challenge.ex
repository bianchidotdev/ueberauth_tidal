defmodule UeberauthTidal.Challenge do
  @code_verifier_length 64

  def get_code_challenge(code) when is_binary(code) do
    %{
      code_challenge: generate_code_challenge(code),
      code_challenge_method: "S256"
    }
  end

  def generate_code_challenge(code) do
    :crypto.hash(:sha256, code)
    |> Base.url_encode64(padding: false)
  end

  def generate_code_verifier() do
    @code_verifier_length
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
    |> binary_part(0, @code_verifier_length)
  end
end
