# Spike A: CloudKit Web Services sign-in and private-DB access from a Chrome/Edge extension

Status: ready-for-human
Type: research
Blocked by: 01

`docs/spec.md` §8.3 and §14 Phase 0 (deferred here by ADR-0011). Build a throwaway MV3 extension that signs in with an Apple ID and reads and writes the **private** database through CloudKit Web Services. Record the working setup as an ADR-0004 addendum.

The human part (CloudKit Console tokens, signing in with a real Apple ID) comes first, so this is `ready-for-human`. Once the tokens exist, an agent can build the spike.

Everything below marked **(verify)** is written from Apple's docs and memory, not tested yet.

## Why REST and not CloudKit JS (decided; see `../spec.md`)

- MV3 forbids remotely hosted code, and CloudKit JS is loaded from `cdn.apple-cloudkit.com/ck/2/cloudkit.js`.
- Vendoring it isn't an option: there's no npm package, no redistribution license, and it's a frozen, minified Apple build that store review would have to accept.
- It assumes a window: `window.open` + `postMessage` sign-in, and cookie or `localStorage` sessions. The MV3 service worker has none of these, and an offscreen document just to host it is more machinery than the REST calls themselves.
- The REST surface we need is six endpoints: `users/current`, `zones/modify`, `records/modify`, `records/lookup`, `changes/zone`, and `assets/upload`. A typed adapter in `packages/storage` stays small and testable against a fake (ADR-0004: "the TypeScript adapter stays small and heavily tested").
- Server-to-server key auth can't help: it reaches the **public** database only.

## Human steps: CloudKit Console API tokens

Container `iCloud.com.cedarlogic.satchel` → **Settings → Tokens & Keys → API Tokens → +**. Development and Production are separate environments, so tokens are created per environment.

| Field | Value | Why |
|---|---|---|
| Name | `chrome-dev` (Development) now; `chrome-prod`, `edge-prod` (Production) before release | One token per callback URL, so per extension ID |
| **Sign-in Callback** | **URL Redirect** → `https://<extension-id>.chromiumapp.org/cloudkit` | `chrome.identity.launchWebAuthFlow` resolves when the browser lands on this URL. "Post Message" is the CloudKit JS popup mode; don't use it |
| **Allowed Origins** | **Any domain** to start (verify) | Fetches carry `Origin: chrome-extension://<id>`, and the specific-domains list may not accept that scheme. If it does, lock it down and record that |
| User discoverability | off | Not needed |

Get the `<extension-id>` first:
- **Dev (unpacked):** pin the ID with `manifest.key`, using the public key from the Chrome Web Store dashboard item (create a draft item to get one), so the unpacked ID and the store ID match. Without `key`, the unpacked ID depends on the folder path and the callback breaks.
- **Edge:** Edge Add-ons assigns a **different** ID, so it gets its own token (`edge-prod`). `chrome.identity.getRedirectURL()` returns a `chromiumapp.org` URL in Edge too (verify).
- **Decision (proposed):** separate tokens per store × environment rather than a relay page on GitHub Pages. Tokens are free, and a relay page is one more surface that handles auth tokens. Revisit only if Console rejects `chromiumapp.org` callbacks. Then the fallback is a static page in `site/` that forwards `ckWebAuthToken` to the `chromiumapp.org` URL.

Also check:
- `recordName` is queryable on `Item` (spec §8.2).
- Update `docs/setup/apple.md` step 6, which currently says to skip API tokens, with these exact steps once they're proven.

## Where the API token lives

Spec §8.3 says the API token isn't a secret (it ships in the client and is scoped to one container and environment), but AGENTS.md says never commit API keys. Proposed: keep it out of the repo. Read it from `config/local.config.json` locally and from a CI secret for store builds, and expose it to WXT through `import.meta.env` (for example `WXT_CK_API_TOKEN`). It still ends up in the shipped zip. This just keeps the repo rule simple and makes token rotation a config change. Record the decision in the addendum.

The web auth token lives in `chrome.storage.local`, never `storage.sync` (spec §8.3).

## CORS (expected to be a non-issue; verify)

- A `fetch` from an MV3 **service worker or extension page** to a host in `host_permissions` isn't subject to CORS.
- Never call CloudKit from a **content script**. Content scripts run under the page's origin and would be blocked. All calls go through the background worker (already the architecture).
- The real risk is server-side: **Allowed Origins** rejecting `chrome-extension://<id>`. The first `users/current` call shows it.
- Keep requests "simple": tokens go in the query string as the API expects, the body is JSON sent as `text/plain`, and there are no custom headers.

## Snippets to start from

These are a starting point, not final code. The final adapter belongs in `packages/storage`, and anything touching `chrome.*` belongs in `apps/extension/src/platform/` (AGENTS.md conventions).

### Request wrapper (`packages/storage/src/cloudkit-web/client.ts`)

```ts
import app from '../../../../config/app.config.json' with { type: 'json' };

export type CkEnv = 'development' | 'production';

export interface CkAuthStore {
  get(): Promise<string | undefined>;           // ckWebAuthToken
  set(token: string | undefined): Promise<void>;
}

export class AuthRequiredError extends Error {
  constructor(readonly redirectURL: string) { super('AUTHENTICATION_REQUIRED'); }
}

export class CloudKitClient {
  private readonly base: string;
  constructor(
    private readonly apiToken: string,
    env: CkEnv,
    private readonly auth: CkAuthStore,
    private readonly fetchImpl: typeof fetch = fetch,
  ) {
    this.base = `https://api.apple-cloudkit.com/database/1/${app.apple.iCloudContainer}/${env}/private`;
  }

  async call<T>(path: string, body?: unknown): Promise<T> {
    const url = new URL(`${this.base}/${path}`);
    url.searchParams.set('ckAPIToken', this.apiToken);
    const web = await this.auth.get();
    if (web) url.searchParams.set('ckWebAuthToken', web); // URL encodes it; the token contains + / =

    const res = await this.fetchImpl(url, {
      method: body === undefined ? 'GET' : 'POST',
      headers: body === undefined ? undefined : { 'Content-Type': 'text/plain' }, // simple request, no preflight
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const json = await res.json();

    if (res.status === 421 || json.serverErrorCode === 'AUTHENTICATION_REQUIRED') {
      await this.auth.set(undefined);
      throw new AuthRequiredError(json.redirectURL);
    }
    if (!res.ok) throw new CloudKitError(res.status, json); // THROTTLED → honor json.retryAfter
    // Spike: if responses carry a rotated web auth token, persist it here.
    return json as T;
  }
}
```

### Sign-in (`apps/extension/src/platform/cloudkit-auth.ts`, the only file that touches `chrome.identity`)

```ts
const KEY = 'ckWebAuthToken';

export const chromeAuthStore: CkAuthStore = {
  get: async () => (await chrome.storage.local.get(KEY))[KEY],
  set: async (t) => (t ? chrome.storage.local.set({ [KEY]: t }) : chrome.storage.local.remove(KEY)),
};

export async function signIn(client: CloudKitClient): Promise<CkUser> {
  try {
    return await client.call<CkUser>('users/current'); // already signed in
  } catch (e) {
    if (!(e instanceof AuthRequiredError)) throw e;
    // The callback in CloudKit Console must equal chrome.identity.getRedirectURL('cloudkit')
    const final = await chrome.identity.launchWebAuthFlow({ url: e.redirectURL, interactive: true });
    const token = new URL(final!).searchParams.get('ckWebAuthToken'); // verify the parameter name
    if (!token) throw new Error('Sign-in returned no ckWebAuthToken');
    await chromeAuthStore.set(token);
    const user = await client.call<CkUser>('users/current');
    await ensureLibraryZone(client);
    return user;
  }
}
```

### Zone, save with optimistic concurrency, and sync

```ts
const zoneID = { zoneName: app.apple.cloudKitZone }; // "Library"

// Web clients must create the zone: the iOS app may never have run for this user.
export async function ensureLibraryZone(ck: CloudKitClient) {
  await ck.call('zones/modify', { operations: [{ operationType: 'create', zone: { zoneID } }] });
}

export async function putItem(ck: CloudKitClient, item: Item, body: string, ifVersion?: string) {
  const res = await ck.call<{ records: CkRecordOrError[] }>('records/modify', {
    zoneID,
    atomic: false,
    operations: [{
      operationType: ifVersion ? 'update' : 'create',
      record: {
        recordName: item.id,
        recordType: 'Item',
        recordChangeTag: ifVersion, // the server rejects the write if it's stale → ConflictError (spec §8.1)
        fields: {
          schemaVersion: { value: 1, type: 'INT64' },
          kind: { value: item.kind },
          url: { value: item.url },
          normalizedUrl: { value: item.normalizedUrl },
          title: { value: item.title },
          createdAt: { value: Date.parse(item.createdAt), type: 'TIMESTAMP' },
          tags: { value: item.tags, type: 'STRING_LIST' },
          body: { value: body }, // ≤ 512 KB, otherwise bodyAsset (below)
        },
      },
    }],
  });
  const r = res.records[0];
  // Per-record errors arrive inside a 200 response
  if ('serverErrorCode' in r) {
    if (r.serverErrorCode === 'CONFLICT') throw new ConflictError(await lookup(ck, item.id));
    throw new CloudKitError(200, r);
  }
  return { version: r.recordChangeTag };
}

export async function* pullChanges(ck: CloudKitClient, syncToken?: string) {
  let more = true;
  while (more) {
    const { zones: [z] } = await ck.call<ChangesZoneResponse>('changes/zone', {
      zones: [{ zoneID, syncToken, resultsLimit: 200 }],
    });
    yield { records: z.records, syncToken: z.syncToken }; // persist syncToken after applying each page
    syncToken = z.syncToken;
    more = z.moreComing;
  }
}
```

### Large body as an asset (needs ticket 01's host permission)

```ts
async function uploadBodyAsset(ck: CloudKitClient, recordName: string, markdown: string) {
  const { tokens: [t] } = await ck.call<{ tokens: { url: string }[] }>('assets/upload', {
    zoneID,
    tokens: [{ recordType: 'Item', fieldName: 'bodyAsset', recordName }],
  });
  const up = await fetch(t.url, { method: 'POST', body: new Blob([markdown], { type: 'text/markdown' }) });
  const { singleFile } = await up.json(); // { fileChecksum, size, receipt, ... }
  return { value: singleFile };           // use as fields.bodyAsset, and set fields.body to null
}
```

### Manifest (`apps/extension/wxt.config.ts`)

```ts
host_permissions: chromium
  ? ['https://api.apple-cloudkit.com/*', 'https://*.icloud-content.com/*'] // second host: ticket 01
  : [],
// dev only: pin the unpacked ID so the CloudKit callback URL matches
...(chromium && mode === 'development' ? { key: import.meta.env.WXT_CHROME_PUBLIC_KEY } : {}),
```

## Service-worker rules for the real implementation

- All CloudKit calls go through the background worker. The popup and content scripts only send it messages.
- The worker can be killed at any moment. The IndexedDB outbox is the source of truth, `chrome.alarms` drains it, and there are no in-memory queues.
- On `AUTHENTICATION_REQUIRED`: clear the stored token, keep every outbox item, and prompt for sign-in from a user gesture (popup), not from an alarm.
- Sync uses `changes/zone` with a stored `syncToken`. Queries aren't needed for sync.

## Questions the spike must answer

1. Does CloudKit Console accept a `https://<id>.chromiumapp.org/cloudkit` URL Redirect callback?
2. Does **Allowed Origins** accept `chrome-extension://<id>`, or is "Any domain" required?
3. Which query parameter carries the token on the callback (`ckWebAuthToken`?), and is anything else appended (`ckSession`?)?
4. How long does the web auth token live? Do responses return a rotated token that must replace the stored one?
5. What's the exact error shape on expiry (status 421, `AUTHENTICATION_REQUIRED`, `redirectURL`)?
6. Is `zones/modify` `create` idempotent on an existing zone, or does it need `ZONE_NOT_FOUND` handling?
7. What is the exact asset host from `assets/upload` and from a record's `downloadURL`? Narrow ticket 01's pattern if needed.
8. Does Edge `launchWebAuthFlow` work against its own token and `chromiumapp.org` redirect?
9. Can a record written by the iOS app (CKSyncEngine, `Library` zone) be read back through `records/lookup` and `changes/zone`, with every field type in spec §8.2 decoding correctly?

## Done when

- The spike signs in on Chrome (and Edge if a store ID is available), calls `users/current`, creates or confirms the `Library` zone, writes an `Item`, and reads it back on the iPhone app (Development).
- Questions 1–9 are answered in an ADR-0004 addendum.
- `docs/setup/apple.md` has the proven API-token steps, and spec §8.3's "VERIFY" block is replaced by the answers.
