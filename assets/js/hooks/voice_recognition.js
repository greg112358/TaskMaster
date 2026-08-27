import { playChime, unlockAudioOnGesture } from "../chime";

// How long after we stop talking the microphone stays ignored. Speech results
// arrive slightly behind the audio, so without a tail the end of our own
// sentence gets parsed as a command.
const MIC_MUTE_TAIL_MS = 700;

// Failsafe: some speech engines never fire `onend`. Without this the mic would
// stay ignored for the rest of the session.
const MAX_MUTE_MS = 20000;

// Chrome populates the voice list asynchronously. How long to wait for it
// before giving up, so a platform that never fires `voiceschanged` does not
// hang the alert.
const VOICE_LOAD_TIMEOUT_MS = 1000;

const VoiceRecognition = {
  mounted() {
    this._muted = false;

    // Audio output is set up first and unconditionally: alerts still need to
    // chime and speak on a webview with no speech *recognition* support.
    unlockAudioOnGesture();

    // Server-initiated speech, e.g. "I missed that".
    this.handleEvent("speak", ({ text }) => {
      this.speak(text);
    });

    // An event/task with the alert checkbox set has come due.
    this.handleEvent("alert", ({ text }) => {
      this.announce(text);
    });

    // "Test" button on the Add Event / Task form, dispatched by JS.dispatch so
    // it costs no server round trip.
    this.el.addEventListener("taskmaster:test-alert", () => {
      const input = this.el.querySelector("#add-event-form input[name='title']");
      const title = input ? input.value.trim() : "";
      this.announce(title ? `Alert test. ${title}` : "Alert test");
    });

    this.setupRecognition();
  },

  setupRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

    if (!SpeechRecognition) {
      console.warn("Speech recognition not supported in this browser/webview");
      this.pushEvent("voice_status", { status: "unsupported" });
      return;
    }

    this.recognition = new SpeechRecognition();
    this.recognition.continuous = true;
    this.recognition.interimResults = false;
    this.recognition.lang = "en-US";

    this.recognition.onstart = () => {
      this.pushEvent("voice_status", { status: "listening" });
    };

    this.recognition.onresult = (event) => {
      const last = event.results.length - 1;
      const transcript = event.results[last][0].transcript.trim();

      // Drop anything heard while the app itself is making noise, otherwise a
      // chime plus a read-out task title feeds straight back in as a command.
      if (this._muted) {
        console.log("Voice (ignored, app is speaking):", transcript);
        return;
      }

      console.log("Voice:", transcript);
      this.pushEvent("voice_command", { transcript: transcript });
    };

    this.recognition.onerror = (event) => {
      console.warn("Speech error:", event.error);
      if (event.error === "not-allowed" || event.error === "service-not-allowed") {
        this.pushEvent("voice_status", { status: "denied" });
        return;
      }
      // Auto-restart on transient errors
      this.restartRecognition();
    };

    this.recognition.onend = () => {
      // Auto-restart to keep listening
      this.restartRecognition();
    };

    // Start listening
    this.startRecognition();
  },

  startRecognition() {
    try {
      this.recognition.start();
    } catch (e) {
      // Already started
      console.warn("Recognition start error:", e);
    }
  },

  restartRecognition() {
    clearTimeout(this._restartTimer);
    this._restartTimer = setTimeout(() => {
      this.startRecognition();
    }, 300);
  },

  // Chime, then read the text out once the chime has finished sounding.
  async announce(text) {
    this.mute();
    await playChime();
    this.speak(text);
  },

  async speak(text) {
    const synth = window.speechSynthesis;

    if (!synth) {
      this.reportSpeechUnavailable("this webview has no speech synthesis");
      this.unmute();
      return;
    }

    // With no voices installed, speak() is a silent no-op — which on a wall
    // mounted board looks identical to the alert never firing. Say so instead.
    // (On Linux, Chrome gets its voices from speech-dispatcher.)
    const voices = await this.voices(synth);

    if (voices.length === 0) {
      this.reportSpeechUnavailable("no text-to-speech voices are installed");
      this.unmute();
      return;
    }

    // Chrome's synthesiser can wedge on a queued utterance; clearing first
    // stops one failed alert from silencing every alert after it.
    synth.cancel();

    const utterance = new SpeechSynthesisUtterance(text);
    utterance.rate = 1.0;
    utterance.pitch = 1.0;
    utterance.onend = () => this.unmute();
    utterance.onerror = (event) => {
      this.reportSpeechUnavailable(`speech failed (${event.error})`);
      this.unmute();
    };

    this.mute();
    synth.speak(utterance);
  },

  voices(synth) {
    const loaded = synth.getVoices();
    if (loaded.length > 0) return Promise.resolve(loaded);

    return new Promise((resolve) => {
      let settled = false;
      const settle = () => {
        if (settled) return;
        settled = true;
        resolve(synth.getVoices());
      };

      synth.addEventListener("voiceschanged", settle, { once: true });
      setTimeout(settle, VOICE_LOAD_TIMEOUT_MS);
    });
  },

  reportSpeechUnavailable(reason) {
    console.warn(`Cannot read alerts aloud: ${reason}`);
    this.pushEvent("device_warning", {
      key: "speech",
      message: `can't read alerts aloud: ${reason}`,
    });
  },

  mute() {
    this._muted = true;
    clearTimeout(this._unmuteTimer);
    this._unmuteTimer = setTimeout(() => {
      this._muted = false;
    }, MAX_MUTE_MS);
  },

  unmute() {
    clearTimeout(this._unmuteTimer);
    this._unmuteTimer = setTimeout(() => {
      this._muted = false;
    }, MIC_MUTE_TAIL_MS);
  },

  destroyed() {
    if (this.recognition) {
      this.recognition.onend = null;
      this.recognition.stop();
    }
    clearTimeout(this._restartTimer);
    clearTimeout(this._unmuteTimer);
  },
};

export default VoiceRecognition;
