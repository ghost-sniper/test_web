'use strict';

(() => {
  const themes = new Map([
    ['light', 'Light'],
    ['dark', 'Dark'],
    ['cyberpunk', 'Cyberpunk 2077'],
    ['eva', 'EVA'],
    ['death-stranding', '死亡搁浅'],
    ['wukong', '黑神话：悟空'],
  ]);
  const key = 'mock-studio.theme';
  const root = document.documentElement;
  let initial = 'light';
  try {
    const saved = localStorage.getItem(key);
    if (themes.has(saved)) initial = saved;
  } catch {
    // Theme switching still works when browser storage is unavailable.
  }
  root.dataset.theme = initial;

  document.addEventListener('DOMContentLoaded', () => {
    const pickers = document.querySelectorAll('[data-theme-picker]');
    for (const picker of pickers) {
      for (const [value, label] of themes) picker.add(new Option(label, value));
      picker.value = root.dataset.theme;
      picker.addEventListener('change', () => {
        if (!themes.has(picker.value)) return;
        const selected = picker.value;
        root.dataset.theme = selected;
        for (const other of pickers) other.value = selected;
        try {
          localStorage.setItem(key, selected);
        } catch {
          // Keep the current selection for this page.
        }
      });
    }
  }, { once: true });
})();
