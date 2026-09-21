defmodule TaskmasterWeb.ErrorMessage do
  @moduledoc """
  The one place a rejected write is turned into a string.

  Format is fixed by the `deslop` skill: name the field and the value that was
  refused, because "couldn't save that" is no more useful than silence.

      Missing field: title
      Invalid field: name="Greg" (has already been taken)
      Invalid field: youtube_url="ftp://x" (must be an http or https URL)

  Every screen routes its `{:error, changeset}` through here rather than writing
  a message at the call site.
  """

  alias TaskmasterWeb.CoreComponents

  @doc "A one-line description of the first error on a rejected changeset."
  def build(%Ecto.Changeset{errors: [{field, error} | _]} = changeset) do
    case CoreComponents.translate_error(error) do
      "can't be blank" ->
        "Missing field: #{field}"

      constraint ->
        "Invalid field: #{field}=#{inspect(rejected_value(changeset, field))} (#{constraint})"
    end
  end

  def build(%Ecto.Changeset{}), do: "Write rejected"

  # What was typed, not what it cast to — a value that failed to cast has no
  # entry in `changes` at all.
  defp rejected_value(changeset, field) do
    case Map.fetch(changeset.params || %{}, to_string(field)) do
      {:ok, value} -> value
      :error -> Ecto.Changeset.get_field(changeset, field)
    end
  end
end
