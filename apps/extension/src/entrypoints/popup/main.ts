const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
const title = document.querySelector<HTMLParagraphElement>('#tab-title');
if (title) title.textContent = tab?.title ?? tab?.url ?? '';
