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
  const rate = 48000,
    count = rate * 3,
    wav = Buffer.alloc(44 + count * 2);
  wav.write('RIFF', 0);
  wav.writeUInt32LE(wav.length - 8, 4);
  wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20);
  wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(rate, 24);
  wav.writeUInt32LE(rate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write('data', 36);
  wav.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++)
    wav.writeInt16LE(Math.round(Math.sin((2 * Math.PI * 880 * i) / rate) * 7000), 44 + i * 2);
  await page
    .locator('#audio-file')
    .setInputFiles({name: 'Music.wav', mimeType: 'audio/wav', buffer: wav});
  await page.getByLabel('file audio volume').waitFor();
  await page.getByLabel('file audio start in edited video').fill('0.5');
  await page.getByLabel('file audio start in edited video').press('Tab');
  await page.getByLabel('Original audio volume').fill('0');
  await page.getByLabel('Original audio volume').dispatchEvent('change');
  await page.getByRole('button', {name: 'Save copy'}).click();
  await page.getByRole('link', {name: 'Open copy'}).waitFor({timeout: 20000});
  const copyId = new URL(
    await page.getByRole('link', {name: 'Open copy'}).getAttribute('href'),
    page.url(),
  ).searchParams.get('preview');
  const audioResult = await page.evaluate(async (id) => {
    const db = await import('/src/storage.ts');
    const row = (await db.list()).find((r) => r.id === id);
    const ctx = new AudioContext();
    const buffer = await ctx.decodeAudioData(await (await db.readBlob(row)).arrayBuffer());
    const data = buffer.getChannelData(0),
      rate = buffer.sampleRate;
    function rms(start, end) {
      let sum = 0,
        n = 0;
      for (let i = Math.floor(start * rate); i < Math.min(data.length, end * rate); i++) {
        sum += data[i] * data[i];
        n++;
      }
      return Math.sqrt(sum / n);
    }
    function energy(hz) {
      let re = 0,
        im = 0;
      const start = Math.floor(0.8 * rate),
        n = 4096;
      for (let i = 0; i < n; i++) {
        re += data[start + i] * Math.cos((2 * Math.PI * hz * i) / rate);
        im += data[start + i] * Math.sin((2 * Math.PI * hz * i) / rate);
      }
      return Math.hypot(re, im) / n;
    }
    const result = {
      silent: rms(0.1, 0.3),
      audible: rms(0.8, 1),
      music: energy(880),
      original: energy(440),
    };
    await ctx.close();
    return result;
  }, copyId);
  if (
    audioResult.silent > 0.005 ||
    audioResult.audible < 0.03 ||
    audioResult.music < 0.02 ||
    audioResult.original > 0.005
  )
    throw new Error('Wrong mix ' + JSON.stringify(audioResult));
  await page.evaluate(() => {
    navigator.mediaDevices.getUserMedia = async () => {
      const ctx = new AudioContext();
      void ctx.resume();
      const osc = ctx.createOscillator();
      osc.frequency.value = 660;
      const gain = ctx.createGain();
      gain.gain.value = 0.2;
      const dest = ctx.createMediaStreamDestination();
      osc.connect(gain).connect(dest);
      osc.start();
      window.micTest = {ctx, osc, stream: dest.stream};
      return dest.stream;
    };
  });
  await page.getByRole('button', {name: 'Record voiceover', exact: true}).click();
  await page.getByLabel('voice audio volume').waitFor({timeout: 15000});
  if ((await page.getByLabel('Original audio volume').inputValue()) !== '0')
    throw new Error('Dub did not mute original');
  if (
    await page.evaluate(() =>
      window.micTest.stream.getTracks().some((t) => t.readyState === 'live'),
    )
  )
    throw new Error('Microphone left live');
  await page.getByRole('button', {name: 'Record voiceover', exact: true}).click();
  await page.locator('#voice-cancel').click();
  await page.waitForFunction(() => document.querySelector('.voice-controls').hidden);
  if ((await page.getByLabel('voice audio volume').count()) !== 1)
    throw new Error('Cancel lost existing voiceover');
  await page.getByRole('button', {name: 'Save copy'}).click();
  await page.getByRole('link', {name: 'Open copy'}).waitFor({timeout: 20000});

  const voiceCopy = new URL(
    await page.getByRole('link', {name: 'Open copy'}).getAttribute('href'),
    page.url(),
  ).searchParams.get('preview');
  const voiceEnergy = await page.evaluate(async (id) => {
    const db = await import('/src/storage.ts');
    const row = (await db.list()).find((r) => r.id === id);
    const ctx = new AudioContext();
    const b = await ctx.decodeAudioData(await (await db.readBlob(row)).arrayBuffer());
    const data = b.getChannelData(0);
    let re = 0,
      im = 0;
    for (let i = 0; i < 4096; i++) {
      const v = data[Math.floor(0.2 * b.sampleRate) + i];
      re += v * Math.cos((2 * Math.PI * 660 * i) / b.sampleRate);
      im += v * Math.sin((2 * Math.PI * 660 * i) / b.sampleRate);
    }
    await ctx.close();
    return Math.hypot(re, im) / 4096;
  }, voiceCopy);
  if (voiceEnergy < 0.03) throw new Error('Voiceover missing from exported mix: ' + voiceEnergy);
  await page.setViewportSize({width: 390, height: 844});
  await page.waitForTimeout(100);
  if (await page.evaluate(() => document.documentElement.scrollWidth > innerWidth))
    throw new Error('Mobile overflow');
  await page.setViewportSize({width: 1000, height: 850});
  await page.screenshot({
    fullPage: true,
    path: fileURLToPath(new URL('../output/playwright/audio-editor.png', import.meta.url)),
  });
  await page.evaluate(() => {
    window.micTest.osc.stop();
    void window.micTest.ctx.close();
  });
  return {
    audioResult,
    voiceEnergy,
    voiceover: 'recorded',
    microphoneCleanup: 'passed',
    cancel: 'passed',
  };
};
