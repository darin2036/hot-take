export const inputNames = ['camera', 'mic', 'audio'] as const;
export type InputName = (typeof inputNames)[number];
type PreferenceStore = Pick<Storage, 'getItem' | 'setItem'>;
export function readInput(name: InputName, store?: PreferenceStore): boolean {
  try {
    return (store ?? localStorage).getItem(`relaytake.input.${name}`) !== 'false';
  } catch {
    return true;
  }
}
export function saveInput(name: InputName, enabled: boolean, store?: PreferenceStore) {
  try {
    (store ?? localStorage).setItem(`relaytake.input.${name}`, String(enabled));
  } catch {
    /* Storage may be disabled; the current selection still works. */
  }
}
export function bindInputs(params = new URLSearchParams(), canSync = () => true) {
  for (const name of inputNames) {
    const input = document.getElementById(name) as HTMLInputElement;
    const explicit = params.get(name);
    input.checked = explicit === '0' ? false : explicit === '1' ? true : readInput(name);
    input.addEventListener('change', () => saveInput(name, input.checked));
  }
  window.addEventListener('storage', (event) => {
    if (!canSync()) return;
    for (const name of inputNames) {
      if (event.key === null || event.key === `relaytake.input.${name}`) {
        (document.getElementById(name) as HTMLInputElement).checked = readInput(name);
      }
    }
  });
}
