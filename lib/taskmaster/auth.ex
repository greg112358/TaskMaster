defmodule Taskmaster.Auth do
  @moduledoc """
  Reads the board's single username and password from `credentials.txt`.

  The file holds one line, `username:password`. Blank lines and `#` comments are
  skipped, and only the first colon splits, so a password may contain colons.

  The file is read on every check rather than cached, so creating or editing it
  takes effect without restarting the board — which matters, because until it
  exists nothing is reachable to restart anything from.
  """

  @filename "credentials.txt"

  @doc """
  Where the credentials file is looked for.

  An explicitly configured path — app env or `TASKMASTER_CREDENTIALS` — is
  authoritative: if it names a file that is not there, the board is unconfigured
  rather than quietly falling back to some other file. Otherwise the working
  directory is tried, then the config directory, and the first that exists wins.
  """
  def candidate_paths do
    case configured_path() do
      nil ->
        [
          Path.expand(@filename, File.cwd!()),
          Path.join([System.user_home!(), ".config", "taskmaster", @filename])
        ]

      path ->
        [path]
    end
  end

  def credentials_path do
    paths = candidate_paths()
    Enum.find(paths, List.first(paths), &File.exists?/1)
  end

  defp configured_path do
    Application.get_env(:taskmaster, :credentials_path) ||
      System.get_env("TASKMASTER_CREDENTIALS")
  end

  @doc "`{:ok, %{username: _, password: _}}`, or `:error` if there is no usable file."
  def credentials do
    with {:ok, contents} <- File.read(credentials_path()),
         [line | _] <- usable_lines(contents),
         [username, password] <- String.split(line, ":", parts: 2),
         true <- username != "" and password != "" do
      {:ok, %{username: username, password: password}}
    else
      _ -> :error
    end
  end

  def configured?, do: credentials() != :error

  @doc "Whether a supplied pair matches, compared in constant time."
  def verify(username, password) do
    case credentials() do
      {:ok, credentials} ->
        # Both compared, never short-circuited, so a wrong username and a wrong
        # password take the same time.
        ok_user = Plug.Crypto.secure_compare(username, credentials.username)
        ok_pass = Plug.Crypto.secure_compare(password, credentials.password)
        ok_user and ok_pass

      :error ->
        false
    end
  end

  @doc """
  A stable digest of the current credentials.

  It is what the "remember me" cookie stores, so editing `credentials.txt`
  invalidates every browser that had been let in under the old pair.
  """
  def fingerprint do
    case credentials() do
      {:ok, %{username: username, password: password}} ->
        {:ok,
         :sha256
         |> :crypto.hash(username <> ":" <> password)
         |> Base.encode16(case: :lower)}

      :error ->
        :error
    end
  end

  defp usable_lines(contents) do
    contents
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
  end
end
