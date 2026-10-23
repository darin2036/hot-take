import {getThumbnail, saveThumbnail, readPrefix, type Recording} from './storage';

function renderFrame(blob: Blob): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video');
    const url = URL.createObjectURL(blob);
    video.muted = true;
    video.playsInline = true;
    video.preload = 'auto';
    const cleanup = () => {
      clearTimeout(timeout);
      video.onloadeddata = null;
      video.onerror = null;
      video.pause();
      video.removeAttribute('src');
      video.load();
      URL.revokeObjectURL(url);
    };
    const fail = () => {
      cleanup();
      reject(new Error('Thumbnail unavailable'));
    };
    const timeout = setTimeout(fail, 5000);
    video.onerror = fail;
    video.onloadeddata = () => {
      try {
        if (!video.videoWidth || !video.videoHeight) {
          fail();
          return;
        }
        const canvas = document.createElement('canvas');
        canvas.width = 320;
        canvas.height = 180;
        const ctx = canvas.getContext('2d')!;
        ctx.fillStyle = '#181b2a';
        ctx.fillRect(0, 0, 320, 180);
        const scale = Math.min(320 / video.videoWidth, 180 / video.videoHeight);
        const width = video.videoWidth * scale,
          height = video.videoHeight * scale;
        ctx.drawImage(video, (320 - width) / 2, (180 - height) / 2, width, height);
        cleanup();
        canvas.toBlob(
          (image) => (image ? resolve(image) : reject(new Error('Thumbnail unavailable'))),
          'image/webp',
          0.8,
        );
      } catch {
        fail();
      }
    };
    video.src = url;
  });
}

/** Serial decoding keeps library loading bounded. Failed recovery uses the play fallback. */
export class ThumbnailQueue {
  private generation = 0;
  private pending = Promise.resolve();
  private urls: string[] = [];
  reset() {
    this.generation++;
    this.urls.forEach((url) => URL.revokeObjectURL(url));
    this.urls = [];
  }
  add(row: Recording, target: HTMLElement) {
    const generation = this.generation;
    this.pending = this.pending.then(async () => {
      if (generation !== this.generation || !target.isConnected) return;
      try {
        let thumbnail = await getThumbnail(row.id);
        if (!thumbnail) {
          thumbnail = await renderFrame(await readPrefix(row));
          await saveThumbnail(row.id, thumbnail);
        }
        if (generation !== this.generation || !target.isConnected) return;
        const url = URL.createObjectURL(thumbnail);
        this.urls.push(url);
        const image = document.createElement('img');
        image.src = url;
        image.alt = '';
        image.width = 160;
        image.height = 90;
        target.classList.add('has-thumbnail');
        target.replaceChildren(image);
      } catch {
        /* Leave the accessible recording action and its fallback icon intact. */
      }
    });
  }
}
