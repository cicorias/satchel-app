// Share Extension preprocessing (spec §9.2.2): when Satchel is picked from Safari's share sheet, Safari runs this in
// the shared page and hands the result to the extension. The staging script appends it to capture.iife.js
// (globalThis.SatchelCapture) as SatchelSharePreprocessing.js. The extension decodes the result with SatchelKit's
// SafariShareCapture. Markdown travels as a string; images are never loaded here.

(() => {
  const message = (error) => (error && error.message) || String(error);

  globalThis.ExtensionPreprocessingJS = {
    run(args) {
      const api = globalThis.SatchelCapture;
      const pageUrl = document.location.href;
      const result = { url: pageUrl, title: document.title };
      const finish = () => args.completionFunction({ satchel: JSON.stringify(result) });
      if (!api) {
        result.linkError = result.pageError = 'The capture engine didn’t load.';
        return finish();
      }
      const options = { pageUrl, client: 'ios-share', version: api.version };
      try {
        result.link = api.itemFromCapture(api.captureLink(document, { pageUrl }), options);
      } catch (error) {
        result.linkError = message(error);
      }
      api.capturePage(document, { pageUrl }).then(
        (capture) => {
          result.page = api.itemFromCapture(capture, options);
          finish();
        },
        (error) => {
          result.pageError =
            error && error.name === 'PageTooLargeError'
              ? 'This page is too large to save as a page.'
              : `The page couldn’t be captured: ${message(error)}`;
          finish();
        },
      );
    },
    finalize() {},
  };
})();
