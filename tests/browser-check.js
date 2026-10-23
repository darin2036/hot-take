async (page) => {
  await page.goto(new URL('index.html?view=studio', page.url()).href);
  await page.evaluate(async () => {
    const db = await import('/src/storage.ts');
    for (const row of await db.list()) await db.remove(row.id);
  });
  await page.reload();
  await page.evaluate(() => {
    navigator.mediaDevices.getDisplayMedia = async () => {
      const canvas = document.createElement('canvas');
      canvas.width = 640;
      canvas.height = 360;
      const ctx = canvas.getContext('2d');
      let tick = 0;
      const draw = () => {
        ctx.fillStyle = '#234b3f';
        ctx.fillRect(0, 0, 640, 360);
        ctx.fillStyle = '#e4eccd';
        ctx.font = '32px sans-serif';
        ctx.fillText('Hot Take synthetic demo ' + tick++, 30, 160);
      };
      draw();
      const timer = setInterval(draw, 100);
      const stream = canvas.captureStream(10);
      stream.getTracks()[0].addEventListener('ended', () => clearInterval(timer));
      return stream;
    };
  });
  await page.getByLabel('Recording settings', {exact: true}).click();
  for (const id of ['camera', 'mic', 'audio']) await page.locator('#' + id).uncheck();
  await page.keyboard.press('Escape');
  await page.getByRole('textbox', {name: 'Recording title'}).fill('Synthetic recording test');
  await page.getByRole('button', {name: 'Start recording'}).click();
  await page.getByRole('button', {name: 'Pause', exact: true}).waitFor();
  await page.waitForTimeout(1500);
  await page.getByRole('button', {name: 'Pause', exact: true}).click();
  const paused = await page.locator('#timer').innerText();
  await page.waitForTimeout(1100);
  if ((await page.locator('#timer').innerText()) !== paused)
    throw new Error('Paused clock advanced');
  await page.getByRole('button', {name: 'Resume', exact: true}).click();
  await page.waitForTimeout(1500);
  await page.getByRole('button', {name: 'Stop & save'}).click();
  await page.locator('button.take-open').first().waitFor();
  await page.locator('button.take-open').first().click();
  await page.getByRole('dialog').waitFor();
  const playback = await page.locator('#playback').evaluate(async (video) => {
    await video.play();
    await new Promise((resolve) => setTimeout(resolve, 350));
    return {
      width: video.videoWidth,
      height: video.videoHeight,
      currentTime: video.currentTime,
      error: video.error?.message,
    };
  });
  if (!playback.width || !playback.currentTime || playback.error)
    throw new Error('Playback failed ' + JSON.stringify(playback));
  await page.getByRole('button', {name: 'Close preview'}).click();
  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', {name: 'Download', exact: true}).click();
  const download = await downloadPromise;
  if (!/^Synthetic recording test\.(mp4|webm)$/.test(download.suggestedFilename()))
    throw new Error('Bad download name');
  await page.reload();
  await page.locator('button.take-open').first().waitFor();
  console.log(
    JSON.stringify({
      pause: 'passed',
      playback,
      download: download.suggestedFilename(),
      reloadPersistence: 'passed',
    }),
  );
};
