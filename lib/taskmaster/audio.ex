defmodule Taskmaster.Audio do
  @moduledoc """
  One switch over everything on this board that uses the microphone or the
  speakers: speech recognition, speech synthesis, the alert chime, and the
  scheduler that drives it.

  **Off by default.** Turn it back on with `TASKMASTER_AUDIO=1` in the
  environment, or `config :taskmaster, audio: true`.

  With it off:

    * `TaskmasterWeb.AppLive` does not attach the `VoiceRecognition` hook, so
      the page never constructs a `SpeechRecognition`, an `AudioContext` or a
      `SpeechSynthesisUtterance` — the browser is never asked for the
      microphone, and nothing can make a sound;
    * the voice hint bar, the "Chime and read aloud" checkbox, its Test button
      and the bell markers are not rendered;
    * `Taskmaster.Events.AlertScheduler` is not started, so a due `alert` row
      is never marked `last_alerted_on` and never broadcast.

  Nothing is removed: the `alert` column, `Taskmaster.Voice.Parser`, the JS
  hook and `assets/js/chime.js` all stay as they are. This gates them.
  """

  @doc "True when the audio/mic half of the board is turned on."
  def enabled?, do: Application.get_env(:taskmaster, :audio, false) == true
end
