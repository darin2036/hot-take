async (page) => {
  await page.goto('http://127.0.0.1:5173/index.html?view=studio');
  await page.evaluate(() => {
    for (const name of ['camera', 'mic', 'audio'])
      localStorage.setItem('relaytake.input.' + name, 'false');
  });
  await page.reload();
  await page.evaluate(() => {
    navigator.mediaDevices.getDisplayMedia = async () => {
      const canvas = document.createElement('canvas');
      canvas.width = 640;
      canvas.height = 360;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = 'purple';
      ctx.fillRect(0, 0, 640, 360);
      const stream = canvas.captureStream(10);
      window.testSource = stream;
      window.testDraw = setInterval(() => {
        ctx.fillRect(0, 0, 640, 360);
      }, 100);
      return stream;
    };
  });
  const before = await page.evaluate(async () =>
    (await (await import('/src/storage.ts')).list()).map((r) => r.id),
  );
  await page.locator('#start').click();
  await page.waitForFunction(() => document.querySelector('#countdown').textContent === '3');
  for (const digit of ['2', '1'])
    await page.waitForFunction(
      (n) => document.querySelector('#countdown').textContent === n,
      digit,
    );
  await page.waitForFunction(() => document.querySelector('#state').textContent === 'Recording');
  const pip = await page.evaluate(() => !!window.documentPictureInPicture?.window);
  await page.waitForTimeout(1200);
  const firstId = await page.evaluate(
    async () =>
      (await (await import('/src/storage.ts')).list()).find((r) => r.status === 'recording').id,
  );
  // Exercise the same command as the toolbar popup, also when paused.
  await page.locator('#pause').click();
  const restarted = await page.evaluate(async () => {
    const controls = await import('/src/control.ts');
    const s = await controls.requestControl('status');
    return controls.requestControl('restart', s.owner);
  });
  if (restarted.state !== 'saving') throw new Error('Restart was not acknowledged');
  await page.waitForFunction(
    () =>
      document.querySelector('#countdown').textContent === '3' &&
      !document.querySelector('#countdown').hidden,
  );
  await page.waitForFunction(() => document.querySelector('#state').textContent === 'Recording');
  if ((await page.evaluate(() => window.testSource.getVideoTracks()[0].readyState)) !== 'live')
    throw new Error('Restart lost source');
  await page.waitForTimeout(1100);
  await page.locator('#stop').click();
  await page.waitForFunction(() => document.querySelector('#state').textContent === 'Saved');
  const rows = await page.evaluate(async () => await (await import('/src/storage.ts')).list());
  const added = rows.filter((r) => !before.includes(r.id));
  if (
    added.length !== 1 ||
    added[0].id === firstId ||
    added[0].duration > 2500 ||
    added[0].duration < 900 ||
    !added[0].size
  )
    throw new Error('Restart output incorrect ' + JSON.stringify(added));
  // Cancel countdown: no empty library item and release ownership.
  await page.locator('#start').click();
  await page.waitForFunction(() => !document.querySelector('#countdown').hidden);
  await page.locator('#stop').click();
  await page.waitForFunction(() => !document.querySelector('#start').disabled);
  await page.waitForTimeout(3200);
  const after = await page.evaluate(async () => await (await import('/src/storage.ts')).list());
  if (after.length !== rows.length) throw new Error('Countdown cancellation left a recording');
  if ((await page.locator('#state').innerText()) === 'Recording')
    throw new Error('Cancelled countdown started recording');
  const result = {
    countdown: '3–2–1',
    restart: 'passed',
    cancel: 'passed',
    pictureInPictureOpened: pip,
    duration: added[0].duration,
  };
  await page.evaluate(() => clearInterval(window.testDraw));
  return result;
};
