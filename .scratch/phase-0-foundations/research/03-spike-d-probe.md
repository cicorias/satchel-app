# Spike D probe (reference copy)

This is the temporary code used for Spikes B and D on 2026-10-21. Results are in the ADR-0005 and ADR-0007 addenda. It's kept here, not compiled, so the device re-check (`issues/08`) can drop it back in.

## How to use it

1. Save the TypeScript below as `apps/extension/src/platform/spike-native-messaging.ts`.
2. In `apps/extension/src/entrypoints/popup/main.ts` (and optionally in `background.ts`), call `runNativeMessagingSpike('popup')`, guarded by `if (import.meta.env.SAFARI && import.meta.env.WXT_SATCHEL_SPIKE === '1')`. Render the returned summary into a `<p>` whose text starts with `spike`.
3. Add the Swift cases below to `SafariWebExtensionHandler.beginRequest`.
4. Build with `WXT_SATCHEL_SPIKE=1`, open the popup, and read the summary. Alternatively, read the handler's log: `xcrun simctl spawn booted log show --last 5m --predicate 'eventMessage BEGINSWITH "SPIKE"'` on a simulator, or Console.app filtered on `SPIKE` for a device.
5. Remove all of it afterward.

## `spike-native-messaging.ts`

```ts
type ProbeResult = { kind: string; bytes: number; ok: boolean; ms: number; detail?: string };

async function send(message: object): Promise<unknown> {
  // Safari ignores the application id; the containing app's extension handler receives it.
  return browser.runtime.sendNativeMessage('application.id', message);
}

async function probe(kind: string, bytes: number, message: object): Promise<ProbeResult> {
  const started = performance.now();
  try {
    const reply = await send(message);
    return { kind, bytes, ok: true, ms: Math.round(performance.now() - started), detail: JSON.stringify(reply).slice(0, 120) };
  } catch (error) {
    return { kind, bytes, ok: false, ms: Math.round(performance.now() - started), detail: String(error).slice(0, 200) };
  }
}

export async function runNativeMessagingSpike(trigger: string): Promise<string> {
  const results: ProbeResult[] = [];
  results.push(await probe('ping', 0, { type: 'ping', trigger }));
  for (const kib of [64, 256, 1024, 2048, 4096, 8192, 16384, 32768, 65536]) {
    const bytes = kib * 1024;
    const result = await probe('request', bytes, { type: 'probe', size: bytes, data: 'x'.repeat(bytes) });
    results.push(result);
    if (!result.ok) break;
  }
  for (const kib of [64, 1024, 4096, 16384]) {
    const bytes = kib * 1024;
    const result = await probe('response', bytes, { type: 'reply', size: bytes });
    results.push(result);
    if (!result.ok) break;
  }
  console.info('[satchel spike]', JSON.stringify(results));
  await send({ type: 'spike-report', trigger, results }).catch(() => undefined);
  return results.map((r) => `${r.kind}:${r.bytes / 1024}K=${r.ok ? `ok/${r.ms}ms` : `FAIL(${r.detail})`}`).join(' ');
}
```

## Handler cases (`SafariWebExtensionHandler.swift`)

```swift
case "probe":
    let received = (message?["data"] as? String)?.utf8.count ?? -1
    log.notice("SPIKE probe declared=\(message?["size"] as? Int ?? -1, privacy: .public) received=\(received, privacy: .public)")
    reply = ["ok": true, "received": received]
case "reply":
    let size = message?["size"] as? Int ?? 0
    reply = ["ok": true, "data": String(repeating: "y", count: size)]
case "spike-report":
    let data = (try? JSONSerialization.data(withJSONObject: message?["results"] ?? [])) ?? Data()
    log.notice("SPIKE report \(String(decoding: data, as: UTF8.self), privacy: .public)")
    reply = ["ok": true]
```
