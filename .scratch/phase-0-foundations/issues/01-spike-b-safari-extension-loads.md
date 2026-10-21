# Spike B (finish): the Safari extension loads on iOS

Status: ready-for-agent
Type: prototype
Blocked by: -

The preliminary findings are in the ADR-0005 addendum: the packager layout is mirrored, and resources are copied to the appex root. What remains is to show that the extension **actually runs**.

## Do

- `mise run run:ios`, then on the iPhone 18 Pro Max simulator go to Settings → Apps → Safari → Extensions → Satchel and turn it on.
- Open a page in Safari and open the Satchel popup from the extensions menu. Confirm the popup renders and the background script starts.
- Check whether `background.service_worker` works on iOS Safari, or whether WXT needs `background.scripts` + `persistent: false` for the Safari target.
- Send one `browser.runtime.sendNativeMessage` call and confirm the handler's echo comes back.

## Done when

- The ADR-0005 addendum records the result, including any `wxt.config.ts` change made for Safari.
- `docs/setup/manual-test-plan.md` exists, with the steps for enabling the extension.
