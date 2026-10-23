export interface Options {
  mic: boolean;
  camera: boolean;
  audio: boolean;
  low: boolean;
}
export interface Capture {
  stream: MediaStream;
  dispose: () => void;
  warnings: string[];
}
export async function acquire(
  displayPromise: Promise<MediaStream>,
  options: Options,
): Promise<Capture> {
  const streams: MediaStream[] = [];
  let context: AudioContext | undefined;
  let frame = 0;
  const videos: HTMLVideoElement[] = [];
  const warnings: string[] = [];
  const dispose = () => {
    cancelAnimationFrame(frame);
    streams.forEach((s) => s.getTracks().forEach((t) => t.stop()));
    videos.forEach((v) => {
      v.pause();
      v.srcObject = null;
    });
    void context?.close();
  };
  try {
    const display = await displayPromise;
    streams.push(display);
    if (options.audio && !display.getAudioTracks().length)
      warnings.push('This source did not provide audio.');
    let mic: MediaStream | undefined;
    let camera: MediaStream | undefined;
    // One combined device request lets the browser handle consent together and reuse grants.
    // Never cache an "already permitted" flag: permissions can be revoked externally.
    if (options.mic || options.camera) {
      try {
        const devices = await navigator.mediaDevices.getUserMedia({
          audio: options.mic ? {echoCancellation: true, noiseSuppression: true} : false,
          video: options.camera ? {width: 640, height: 480} : false,
        });
        streams.push(devices);
        if (options.mic) mic = new MediaStream(devices.getAudioTracks());
        if (options.camera) camera = new MediaStream(devices.getVideoTracks());
      } catch {
        throw new Error(
          'Camera or microphone unavailable. Allow access in your browser, or turn the unavailable input off and retry.',
        );
      }
    }
    const output = new MediaStream();
    const displayTrack = display.getVideoTracks()[0];
    if (displayTrack.readyState === 'ended')
      throw new Error('Screen sharing ended before recording started.');
    if (camera) {
      const video = async (s: MediaStream) => {
        const v = document.createElement('video');
        v.muted = true;
        v.playsInline = true;
        v.srcObject = s;
        videos.push(v);
        await v.play();
        return v;
      };
      const screen = await video(display);
      const cam = await video(camera);
      const canvas = document.createElement('canvas');
      const settings = displayTrack.getSettings();
      const scale = Math.min(1, (options.low ? 1280 : 1920) / (settings.width || 1920));
      canvas.width = Math.round((settings.width || 1920) * scale);
      canvas.height = Math.round((settings.height || 1080) * scale);
      const ctx = canvas.getContext('2d')!;
      const draw = () => {
        ctx.fillStyle = '#101817';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        const ratio = Math.min(
          canvas.width / screen.videoWidth,
          canvas.height / screen.videoHeight,
        );
        ctx.drawImage(
          screen,
          (canvas.width - screen.videoWidth * ratio) / 2,
          (canvas.height - screen.videoHeight * ratio) / 2,
          screen.videoWidth * ratio,
          screen.videoHeight * ratio,
        );
        const size = Math.min(canvas.width, canvas.height) * 0.23;
        const x = canvas.width - size - 24,
          y = canvas.height - size - 24;
        ctx.save();
        ctx.beginPath();
        ctx.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2);
        ctx.clip();
        const crop = Math.min(cam.videoWidth, cam.videoHeight);
        ctx.drawImage(
          cam,
          (cam.videoWidth - crop) / 2,
          (cam.videoHeight - crop) / 2,
          crop,
          crop,
          x,
          y,
          size,
          size,
        );
        ctx.restore();
        frame = requestAnimationFrame(draw);
      };
      draw();
      const composed = canvas.captureStream(30);
      streams.push(composed);
      output.addTrack(composed.getVideoTracks()[0]);
      warnings.push(
        'Webcam is baked into the recording. Keep this recorder window visible to reduce background frame throttling.',
      );
    } else output.addTrack(displayTrack);
    const audio = [...display.getAudioTracks(), ...(mic?.getAudioTracks() || [])];
    if (audio.length) {
      context = new AudioContext();
      await context.resume();
      const destination = context.createMediaStreamDestination();
      audio.forEach((track) => {
        const source = context!.createMediaStreamSource(new MediaStream([track]));
        const gain = context!.createGain();
        gain.gain.value = audio.length > 1 ? 0.7 : 1;
        source.connect(gain).connect(destination);
      });
      destination.stream.getAudioTracks().forEach((t) => output.addTrack(t));
      streams.push(destination.stream);
    }
    streams.push(output);
    displayTrack.addEventListener('ended', () => output.dispatchEvent(new Event('sourceended')));
    return {stream: output, dispose, warnings};
  } catch (error) {
    dispose();
    throw error;
  }
}
// MP4 (H.264/AAC) plays almost everywhere; WebM is the fallback for browsers without MP4 recording.
export const MIME_PREFERENCE = [
  'video/mp4;codecs=avc1.640028,mp4a.40.2',
  'video/mp4;codecs=avc1,mp4a.40.2',
  'video/mp4',
  'video/webm;codecs=vp8,opus',
  'video/webm;codecs=vp9,opus',
  'video/webm',
];
export function supportedMime(
  isSupported: (type: string) => boolean = (type) => MediaRecorder.isTypeSupported(type),
): string {
  return MIME_PREFERENCE.find(isSupported) || '';
}
