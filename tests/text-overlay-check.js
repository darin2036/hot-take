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

  await page.getByRole('button', {name: 'Add text', exact: true}).click();
  await page.getByLabel('Overlay text', {exact: true}).fill('HELLO');
  await page.getByLabel('Text size', {exact: true}).selectOption('large');
  const handle = page.getByRole('button', {name: 'Move text: HELLO', exact: true});
  await handle.waitFor();
  const first = await handle.boundingBox();
  await page.mouse.move(first.x + first.width / 2, first.y + first.height / 2);
  await page.mouse.down();
  await page.mouse.move(first.x + first.width / 2 - 60, first.y + first.height / 2 - 50, {
    steps: 5,
  });
  await page.mouse.up();
  const moved = await handle.boundingBox();
  if (moved.x >= first.x - 40 || moved.y >= first.y - 30) throw new Error('Drag did not move text');
  await page.getByRole('button', {name: 'Undo', exact: true}).click();
  const undone = await handle.boundingBox();
  if (Math.abs(undone.x - first.x) > 2) throw new Error('Drag undo failed');
  await handle.press('ArrowUp');
  await page.getByLabel('Text start in seconds').fill('2.2');
  await page.getByLabel('Text end in seconds').fill('2.8');
  await page.getByLabel('Text size', {exact: true}).focus();
  await page.getByLabel('Selection end in seconds').fill('3');
  await page.getByRole('button', {name: 'Trim to selection'}).click();
  await page.getByLabel('Selection start in seconds').fill('1');
  await page.getByLabel('Selection end in seconds').fill('2');
  await page.getByRole('button', {name: 'Remove selection'}).click();
  await page.locator('#edit-video').evaluate((v) => {
    v.currentTime = 2.4;
  });
  await handle.waitFor();
  await page.setViewportSize({width: 900, height: 850});
  await page.screenshot({
    path: fileURLToPath(new URL('../output/playwright/text-editor.png', import.meta.url)),
  });
  await page.setViewportSize({width: 390, height: 844});
  await page.evaluate(
    () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))),
  );
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  if (overflow) throw new Error('Mobile layout overflow');
  await page.setViewportSize({width: 1000, height: 850});
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
      if (original.duration !== 3200 || copy.duration !== 2000)
        throw new Error('Original changed or cut failed');
      const v = document.createElement('video');
      v.muted = true;
      const url = URL.createObjectURL(await db.readBlob(copy));
      v.src = url;
      await new Promise((resolve, reject) => {
        v.onloadeddata = resolve;
        v.onerror = reject;
      });
      const c = document.createElement('canvas');
      c.width = 320;
      c.height = 180;
      const ctx = c.getContext('2d');
      const counts = [];
      for (const time of [0.3, 1.45, 1.95]) {
        await new Promise((resolve) => {
          v.onseeked = resolve;
          v.currentTime = time;
        });
        ctx.drawImage(v, 0, 0, 320, 180);
        const data = ctx.getImageData(0, 0, 320, 180).data;
        let white = 0;
        for (let i = 0; i < data.length; i += 4)
          if (data[i] > 180 && data[i + 1] > 180 && data[i + 2] > 180) white++;
        counts.push(white);
      }
      URL.revokeObjectURL(url);
      return {counts, originalPreserved: true, duration: copy.duration};
    },
    {originalId, copyId},
  );
  if (result.counts[0] > 10 || result.counts[1] < 40 || result.counts[2] > 10)
    throw new Error('Exported text timing failed: ' + JSON.stringify(result));
  return {...result, drag: 'passed', undo: 'passed', responsive: 'passed'};
};
