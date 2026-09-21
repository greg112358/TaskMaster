defmodule Taskmaster.Wkuk.Sketch do
  @moduledoc """
  One sketch. Shared by every ranker: there is one row per sketch, not one per
  person.

  `title`, `season`, `episode` and `position` are catalogue facts and are never
  edited from the screen. `description` and `youtube_url` are — a correction one
  person makes is a correction for everybody, which is the point.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "wkuk_sketches" do
    field :season, :integer
    field :episode, :integer
    # Running order within the episode. Fixes the order of the unranked pile.
    field :position, :integer
    field :title, :string
    field :description, :string, default: ""
    field :youtube_url, :string
    timestamps()
  end

  @doc """
  The editable half. Title and the catalogue keys are absent on purpose — they
  are seeded once and are not writable from the board.
  """
  def changeset(sketch, attrs) do
    sketch
    |> cast(attrs, [:description, :youtube_url])
    |> update_change(:description, &trim/1)
    |> update_change(:youtube_url, &blank_to_nil/1)
    |> validate_length(:description, max: 200)
    |> validate_youtube_url()
  end

  # Ecto's default `:empty_values` already turns a whitespace-only string into
  # nil before these run, so both have to survive being handed one.
  defp trim(nil), do: nil
  defp trim(value), do: String.trim(value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # Client input, so this only ever rejects — it never raises. Anything that is
  # not an http(s) URL is refused rather than stored and later rendered as a
  # link, which is how a javascript: URL would get onto the page.
  defp validate_youtube_url(changeset) do
    validate_change(changeset, :youtube_url, fn :youtube_url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [youtube_url: "must be an http or https URL"]
      end
    end)
  end
end
