import {fileURLToPath} from 'node:url';
async (page) => {
  await page.goto('http://127.0.0.1:5173/index.html?view=library');
  const originalId = await page.evaluate(async () => {
    const db = await import('/src/storage.ts');
    const canvas = document.createElement('canvas');
    canvas.width = 320;
    canvas.height = 180;
    const ctx = canvas.getContext('2d');
    const start = performance.now();
    const draw = () => {
      ctx.fillStyle = ['#ff0000', '#00ff00', '#0000ff'][
        Math.min(2, Math.floor((performance.now() - start) / 1000))
      ];
      ctx.fillRect(0, 0, 320, 180);
    };
    draw();
    const interval = setInterval(draw, 15);
    const audio = new AudioContext();
    await audio.resume();
    const tone = audio.createOscillator();
    tone.frequency.value = 440;
    const dest = audio.createMediaStreamDestination();
    tone.connect(dest);
    tone.start();
    const stream = canvas.captureStream(30);
    dest.stream.getAudioTracks().forEach((t) => stream.addTrack(t));
    const recorder = new MediaRecorder(stream, {mimeType: 'video/webm;codecs=vp8,opus'});
    const chunks = [];
    recorder.ondataavailable = (e) => chunks.push(e.data);
    recorder.start();
    await new Promise((r) => setTimeout(r, 3200));
    await new Promise((r) => {
      recorder.onstop = r;
      recorder.stop();
    });
    clearInterval(interval);
    tone.stop();
    await audio.close();
    stream.getTracks().forEach((t) => t.stop());
    const id = crypto.randomUUID();
    await db.save({
      id,
      title: 'Editor color test',
      created: Date.now(),
      mime: recorder.mimeType,
      size: 0,
      chunks: 0,
      duration: 3200,
      status: 'recording',
    });
    for (const blob of chunks) await db.append(id, blob);
    await db.finalize(id, 3200);
    return id;
  });
  await page.goto(`http://127.0.0.1:5173/editor.html?id=${originalId}`);
  await page.waitForFunction(() => !document.querySelector('#edit-tools').disabled);
  await page.getByLabel('Selection end in seconds').fill('3');
  await page.getByRole('button', {name: 'Trim to selection'}).click();
  await page.getByLabel('Selection start in seconds').fill('1');
  await page.getByLabel('Selection end in seconds').fill('2');
  await page.getByRole('button', {name: 'Remove selection'}).click();
  if ((await page.locator('#edit-length').innerText()) !== '00:02.0')
    throw new Error('Cut duration wrong');
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  if ((await page.locator('#edit-length').innerText()) !== '00:03.0') throw new Error('Undo wrong');
  await page.getByRole('button', {name: 'Remove selection'}).click();
  await page.setViewportSize({width: 1100, height: 900});
  await page.screenshot({path: fileURLToPath(new URL('../output/playwright/editor.png', import.meta.url))});
  await page.getByRole('button', {name: 'Save copy'}).click();
  await page.getByRole('link', {name: 'Open copy'}).waitFor({timeout: 25000});
  const copyId = new URL(
    await page.getByRole('link', {name: 'Open copy'}).getAttribute('href'),
    page.url(),
  ).searchParams.get('preview');
  const result = await page.evaluate(
    async ({originalId, copyId}) => {
      const db = await import('/src/storage.ts');
      const rows = await db.list();
      const original = rows.find((r) => r.id === originalId),
        copy = rows.find((r) => r.id === copyId);
      if (
        !original ||
        original.status !== 'ready' ||
        original.duration !== 3200 ||
        copy?.status !== 'ready' ||
        copy.duration !== 2000
      )
        throw new Error('Original or copy metadata incorrect');
      const video = document.createElement('video');
      video.muted = true;
      const url = URL.createObjectURL(await db.readBlob(copy));
      video.src = url;
      await new Promise((resolve, reject) => {
        video.onloadeddata = resolve;
        video.onerror = reject;
      });
      const canvas = document.createElement('canvas');
      canvas.width = 1;
      canvas.height = 1;
      const ctx = canvas.getContext('2d');
      const pixels = [];
      for (const time of [0.3, 1.4]) {
        await new Promise((resolve) => {
          video.onseeked = resolve;
          video.currentTime = time;
        });
        ctx.drawImage(video, 0, 0, 1, 1);
        pixels.push(Array.from(ctx.getImageData(0, 0, 1, 1).data));
      }
      video.removeAttribute('src');
      video.load();
      URL.revokeObjectURL(url);
      return {pixels, size: copy.size, originalPreserved: true, duration: copy.duration};
    },
    {originalId, copyId},
  );
  if (
    result.pixels[0][0] < 180 ||
    result.pixels[0][1] > 70 ||
    result.pixels[1][2] < 180 ||
    result.pixels[1][1] > 70
  )
    throw new Error('Deleted green segment leaked: ' + JSON.stringify(result));
  return result;
};
