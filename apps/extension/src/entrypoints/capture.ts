// Injected into the active tab on the user's action (activeTab + scripting, spec §11) before a save. It exposes the
// capture engine as globalThis.SatchelCapture for the function `platform/tab.ts` runs next.

import * as capture from '@satchel/capture';

export default defineUnlistedScript(() => {
  (globalThis as Record<string, unknown>).SatchelCapture = capture;
});
