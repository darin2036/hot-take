import {inputNames, readInput} from './preferences';
import {CHANNEL} from './control';
export const isExtension = typeof chrome !== 'undefined' && Boolean(chrome.runtime?.id);
export async function openSurface(
  view: 'recorder' | 'library',
  options: URLSearchParams = new URLSearchParams(),
) {
  const params = new URLSearchParams(options);
  params.set('view', view);
  if (view === 'recorder')
    for (const name of inputNames)
      if (!params.has(name)) params.set(name, readInput(name) ? '1' : '0');
  const relative = `index.html?${params}`;
  if (!isExtension) {
    window.open(
      relative,
      view === 'recorder' ? 'relaytake-recorder' : '_blank',
      view === 'recorder' ? 'popup,width=540,height=760' : undefined,
    );
    return;
  }
  // Only enumerates this extension's own contexts; no tabs/host permission needed.
  const contexts = await chrome.runtime.getContexts({
    contextTypes: [chrome.runtime.ContextType.TAB],
  });
  const existing = contexts.find((c) => {
    if (!c.documentUrl || c.tabId < 0) return false;
    const url = new URL(c.documentUrl);
    return url.pathname === '/index.html' && url.searchParams.get('view') === view;
  });
  if (existing) {
    if (view === 'library')
      await chrome.tabs.update(existing.tabId, {
        url: chrome.runtime.getURL(relative),
        active: true,
      });
    else {
      const channel = new BroadcastChannel(CHANNEL);
      channel.postMessage({
        type: 'configure',
        ...Object.fromEntries(
          ['mic', 'camera', 'audio']
            .filter((name) => params.has(name))
            .map((name) => [name, params.get(name) === '1']),
        ),
      });
      channel.close();
      await chrome.tabs.update(existing.tabId, {active: true});
    }
    await chrome.windows.update(existing.windowId, {focused: true});
  } else if (view === 'recorder')
    await chrome.windows.create({
      url: chrome.runtime.getURL(relative),
      type: 'popup',
      width: 560,
      height: 800,
      focused: true,
    });
  else await chrome.tabs.create({url: chrome.runtime.getURL(relative)});
}
