// Background service worker (non-persistent on Safari). Phase 2/3: outbox, sync alarms, context menus.

export default defineBackground(() => {
  browser.runtime.onInstalled.addListener(() => {
    console.info('[satchel] installed');
  });
});
