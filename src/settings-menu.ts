/** Native disclosure semantics for form controls, with conventional dismissal. */
export function bindSettingsMenu() {
  const menu = document.querySelector<HTMLDetailsElement>('.settings-menu');
  if (!menu) return;
  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && menu.open) {
      menu.open = false;
      menu.querySelector('summary')?.focus();
    }
  });
  document.addEventListener('click', (event) => {
    if (event.target instanceof Node && !menu.contains(event.target)) menu.open = false;
  });
}
