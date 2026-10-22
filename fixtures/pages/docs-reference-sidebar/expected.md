---
id: u_29956c3d02c043acfcffb6801ca48140
type: page
title: "StorageQueue: drain() method - Web APIs | DevDocs Reference"
url: https://devdocs.example.org/en-US/docs/Web/API/StorageQueue/drain
canonical: https://devdocs.example.org/en-US/docs/Web/API/StorageQueue/drain
site: "DevDocs Reference"
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "The drain() method of the StorageQueue interface returns a Promise that resolves once every pending write in the queue has been flushed to disk."
image: https://devdocs.example.org/devdocs-social-share.png
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# StorageQueue: drain() method - Web APIs | DevDocs Reference

Secure context: This feature is available only in secure contexts (HTTPS), in some or all supporting browsers.

The **`drain()`** method of the [`StorageQueue`](https://devdocs.example.org/en-US/docs/Web/API/StorageQueue) interface returns a [`Promise`](https://devdocs.example.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise) that resolves once every pending write in the queue has been flushed to disk.

Calling `drain()` does not stop new writes from being added. Writes enqueued after the call are not waited for; call `drain()` again if you need them flushed too.

**Note:** On some platforms the operating system may cache writes after the browser hands them off, so a resolved promise means the browser has finished, not necessarily the disk.

## Syntax

```js
drain()
drain(options)
```

### Parameters

`options` Optional

An object with the following property:

`timeout`

The number of milliseconds to wait before rejecting. Defaults to no timeout.

### Return value

A `Promise` that fulfills with `undefined`.

### Exceptions

`TimeoutError` `DOMException`

Returned if the timeout elapses before the queue is empty.

`InvalidStateError` `DOMException`

Returned if the queue was aborted.

## Examples

This example writes a batch of records and waits until all of them are stored before showing a confirmation.

```js
const queue = await navigator.storageQueue.open("drafts");
for (const draft of drafts) {
  queue.enqueue(draft.id, draft);
}
await queue.drain({ timeout: 5000 });
status.textContent = "All drafts saved";
```

## Specifications

| Specification |
| --- |
| [Storage Queue \# dom-storagequeue-drain](https://spec.example.org/storage-queue/#dom-storagequeue-drain) |

## Browser compatibility

|  | Desktop A | Desktop B | Mobile A |
| --- | --- | --- | --- |
| `drain` | 128 | No | 128 |
| `options.timeout` | 131 | No | 131 |
