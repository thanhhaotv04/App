// Keep keyboard position and scroll stable during live data updates.
export function syncList(container, rows, create, update, fallback) {
  const focused = container.contains(document.activeElement)
    ? document.activeElement.closest('[data-key]')?.dataset.key : null;
  const top = container.scrollTop;
  const left = container.scrollLeft;
  const existing = new Map([...container.children].map((node) => [node.dataset.key, node]));
  const wanted = new Set();
  rows.forEach((row, index) => {
    const key = String(row.key);
    wanted.add(key);
    const node = existing.get(key) || create(row);
    node.dataset.key = key;
    update(node, row);
    if (container.children[index] !== node) container.insertBefore(node, container.children[index] || null);
  });
  for (const [key, node] of existing) if (!wanted.has(key)) node.remove();
  if (focused !== null && !container.contains(document.activeElement)) {
    const node = [...container.children].find((child) => child.dataset.key === focused);
    (node?.matches('button') ? node : node?.querySelector('button'))?.focus({ preventScroll: true });
    if (!node) fallback?.focus({ preventScroll: true });
  }
  container.scrollTop = top;
  container.scrollLeft = left;
}

export function confirmAction(title, message, label) {
  const dialog = document.getElementById('confirm-dialog');
  document.getElementById('confirm-title').textContent = title;
  document.getElementById('confirm-message').textContent = message;
  document.getElementById('confirm-ok').textContent = label;
  dialog.returnValue = '';
  return new Promise((resolve) => {
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'confirm'), { once: true });
    dialog.showModal();
  });
}
