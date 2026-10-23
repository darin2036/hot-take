async (page) => {
  const extensionId = await page.evaluate(
    () =>
      Array.from(
        document
          .querySelector('extensions-manager')
          .shadowRoot.querySelector('extensions-item-list')
          .shadowRoot.querySelectorAll('extensions-item'),
      ).find((item) => item.data.name === 'Hot Take').id,
  );
  const base = `chrome-extension://${extensionId}/`;
  const context = page.context();
  let popup = await context.newPage();
  await popup.goto(base + 'popup.html');
  await popup.getByRole('button', {name: 'New recording'}).waitFor();
  await popup.waitForFunction(() => !document.querySelector('#new').disabled);
  if ((await popup.locator('#new').evaluate((el) => getComputedStyle(el).fontSize)) !== '14px')
    throw new Error('Popup button typography drifted');
  await popup.getByLabel('Recording settings', {exact: true}).click();
  for (const id of ['camera', 'mic', 'audio']) await popup.locator('#' + id).uncheck();
  await popup.keyboard.press('Escape');
  const created = context.waitForEvent('page');
  await popup.getByRole('button', {name: 'New recording'}).click();
  const recorder = await created;
  await recorder.waitForLoadState();
  if (!recorder.url().includes('view=recorder')) throw new Error('Recorder window did not open');
  await recorder.evaluate(() => {
    navigator.mediaDevices.getDisplayMedia = async () => {
      const c = document.createElement('canvas');
      c.width = 640;
      c.height = 360;
      const ctx = c.getContext('2d');
      let i = 0;
      const draw = () => {
        ctx.fillStyle = '#234b3f';
        ctx.fillRect(0, 0, 640, 360);
        ctx.fillStyle = '#e4eccd';
        ctx.font = '30px sans-serif';
        ctx.fillText('Extension demo ' + i++, 30, 160);
      };
      draw();
      setInterval(draw, 100);
      return c.captureStream(10);
    };
  });
  await recorder
    .getByRole('textbox', {name: 'Recording title'})
    .fill('A quick product walkthrough');
  await recorder.getByRole('button', {name: 'Choose screen & record'}).click();
  await recorder.getByRole('button', {name: 'Pause', exact: true}).waitFor();
  popup = await context.newPage();
  await popup.goto(base + 'popup.html');
  await popup.getByRole('button', {name: 'Pause', exact: true}).waitFor();
  await popup.waitForTimeout(1200);
  await popup.getByRole('button', {name: 'Pause', exact: true}).click();
  await popup.getByRole('button', {name: 'Resume', exact: true}).waitFor();
  const paused = await recorder.locator('#timer').innerText();
  await popup.waitForTimeout(1200);
  if ((await recorder.locator('#timer').innerText()) !== paused) throw new Error('Pause failed');
  await popup.close();
  popup = await context.newPage();
  await popup.goto(base + 'popup.html');
  await popup.getByRole('button', {name: 'Resume', exact: true}).waitFor();
  await popup.getByRole('button', {name: 'Resume', exact: true}).click();
  await popup.getByRole('button', {name: 'Pause', exact: true}).waitFor();
  await popup.setViewportSize({width: 380, height: 600});
  await popup.screenshot({path: 'output/playwright/popup-recording.png'});
  await popup.close();
  await recorder.waitForTimeout(1500);
  if ((await recorder.locator('#timer').innerText()) === paused)
    throw new Error('Recording did not survive popup close');
  popup = await context.newPage();
  await popup.goto(base + 'popup.html');
  await popup.getByRole('button', {name: 'Stop & save'}).waitFor();
  await popup.getByRole('button', {name: 'Stop & save'}).click();
  await recorder.getByRole('button', {name: 'Preview saved take'}).waitFor();
  await popup.getByRole('button', {name: 'New recording'}).waitFor();
  await popup.setViewportSize({width: 380, height: 650});
  await popup.screenshot({path: 'output/playwright/popup.png'});
  const libraryCreated = context.waitForEvent('page');
  await popup.getByRole('button', {name: 'Library', exact: true}).click();
  const library = await libraryCreated;
  await library.getByRole('button', {name: 'Play A quick product walkthrough'}).click();
  await library.getByRole('dialog').waitFor();
  const playback = await library.locator('#playback').evaluate(async (v) => {
    await v.play();
    await new Promise((r) => setTimeout(r, 300));
    return {width: v.videoWidth, time: v.currentTime};
  });
  if (!playback.width || !playback.time) throw new Error('Preview failed');
  await library.getByRole('button', {name: 'Close preview'}).click();
  await library.reload();
  await library.getByRole('button', {name: 'Play A quick product walkthrough'}).click();
  await library.getByRole('dialog').waitFor();
  await library.getByRole('button', {name: 'Close preview'}).click();
  // Same-origin contexts are reused, without a broad tabs permission.
  popup = await context.newPage();
  await popup.goto(base + 'popup.html');
  await popup.waitForFunction(() => !document.querySelector('#new').disabled);
  await popup.getByLabel('Recording settings', {exact: true}).click();
  await popup.getByRole('checkbox', {name: 'Microphone', exact: true}).check();
  await popup.keyboard.press('Escape');
  const before = context.pages().length;
  await popup.getByRole('button', {name: 'New recording'}).click();
  await recorder.waitForFunction(() => document.querySelector('#mic').checked);
  if (context.pages().length > before) throw new Error('Created duplicate recorder');
  await recorder.getByLabel('Recording settings', {exact: true}).click();
  await recorder.getByRole('checkbox', {name: /Microphone/}).uncheck();
  await recorder.keyboard.press('Escape');
  await recorder.screenshot({path: 'output/playwright/recorder.png', fullPage: true});
  await library.setViewportSize({width: 1280, height: 900});
  await library.screenshot({path: 'output/playwright/library.png', fullPage: true});
  return {
    extensionLoaded: true,
    popupReopen: true,
    pauseResume: true,
    stop: true,
    recentPreview: playback,
    recorderReuse: true,
  };
};
