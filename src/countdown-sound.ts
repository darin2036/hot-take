/** Local synthesized chimes, played before encoding starts. No audio assets or network. */
export class CountdownSound {
  private context?: AudioContext;
  private tones = new Set<OscillatorNode>();
  unlock() {
    try {
      this.context ??= new AudioContext();
      void this.context.resume().catch(() => {});
    } catch {
      /* Sound is optional; recording still works if playback is blocked. */
    }
  }
  ding(final: boolean) {
    const context = this.context;
    if (!context || context.state !== 'running') return;
    const now = context.currentTime,
      length = final ? 0.65 : 0.22;
    const tone = context.createOscillator(),
      gain = context.createGain();
    tone.type = 'sine';
    tone.frequency.value = final ? 1046.5 : 783.99;
    gain.gain.setValueAtTime(0, now);
    gain.gain.linearRampToValueAtTime(final ? 0.22 : 0.14, now + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.001, now + length);
    tone.connect(gain).connect(context.destination);
    this.tones.add(tone);
    tone.onended = () => {
      tone.disconnect();
      gain.disconnect();
      this.tones.delete(tone);
    };
    tone.start(now);
    tone.stop(now + length + 0.02);
  }
  stop() {
    for (const tone of this.tones) {
      tone.stop();
      tone.disconnect();
    }
    this.tones.clear();
  }
  close() {
    this.stop();
    const context = this.context;
    this.context = undefined;
    void context?.close().catch(() => {});
  }
}
