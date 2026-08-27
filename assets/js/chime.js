// Alert chime, synthesised with the Web Audio API.
//
// Doing it in code rather than shipping an audio file keeps the Pi image free
// of binary assets and lets the tone be tuned by editing TONES below. It is a
// two-note "ding" (A5 then E6) with a fast attack and an exponential decay, so
// it carries across a room without sounding like an error beep.

const TONES = [
  { frequency: 880.0, at: 0.0, duration: 0.4 },
  { frequency: 1318.51, at: 0.18, duration: 0.55 },
];

const PEAK_GAIN = 0.35;
const ATTACK_SECONDS = 0.015;

let audioContext = null;

function context() {
  if (!audioContext) {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    audioContext = new Ctx();
  }
  return audioContext;
}

// Browsers refuse to start audio until the page has seen a user gesture. The
// board is a touchscreen, so the first tap unlocks playback for the session;
// we keep listening rather than using `once` because a context can be
// suspended again (screen blank, tab backgrounded) and needs resuming.
export function unlockAudioOnGesture() {
  const resume = () => {
    const ctx = context();
    if (ctx && ctx.state === "suspended") ctx.resume();
  };

  for (const event of ["pointerdown", "touchstart", "keydown"]) {
    window.addEventListener(event, resume, { passive: true });
  }
}

// Plays the chime and resolves once it has finished sounding, so callers can
// await it before starting speech.
export function playChime() {
  const ctx = context();
  if (!ctx) return Promise.resolve();
  if (ctx.state === "suspended") ctx.resume();

  const start = ctx.currentTime + 0.02;
  let finish = start;

  for (const tone of TONES) {
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();

    oscillator.type = "sine";
    oscillator.frequency.value = tone.frequency;

    const toneStart = start + tone.at;
    const toneEnd = toneStart + tone.duration;

    // exponentialRampToValueAtTime cannot ramp to or from 0, hence the
    // near-silent floor at either end of the envelope.
    gain.gain.setValueAtTime(0.0001, toneStart);
    gain.gain.exponentialRampToValueAtTime(PEAK_GAIN, toneStart + ATTACK_SECONDS);
    gain.gain.exponentialRampToValueAtTime(0.0001, toneEnd);

    oscillator.connect(gain).connect(ctx.destination);
    oscillator.start(toneStart);
    oscillator.stop(toneEnd);

    finish = Math.max(finish, toneEnd);
  }

  const remainingMs = Math.max(0, (finish - ctx.currentTime) * 1000);
  return new Promise((resolve) => setTimeout(resolve, remainingMs));
}
