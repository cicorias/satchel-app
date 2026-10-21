import { defineConfig } from 'wxt';
import app from '../../config/app.config.json' with { type: 'json' };

// One codebase, three targets: chrome (MV3), edge (MV3), safari (MV3, forced via --mv3 in package.json
// scripts because WXT defaults Safari to MV2). See spec §9.1 and ADR-0005.
export default defineConfig({
  srcDir: 'src',
  manifestVersion: 3,
  manifest: ({ browser }) => {
    const chromium = browser === 'chrome' || browser === 'edge';
    return {
      name: app.name,
      description: app.description,
      version: app.version,
      homepage_url: app.siteUrl,
      action: { default_title: `Save to ${app.name}` },
      // Minimal permissions (spec §9.1.2). Content scripts are injected on user action only.
      permissions: [
        'activeTab',
        'scripting',
        'storage',
        'contextMenus',
        'alarms',
        ...(chromium ? ['identity', 'offscreen'] : []),
        ...(browser === 'safari' ? ['nativeMessaging'] : []),
      ],
      host_permissions: chromium ? ['https://api.apple-cloudkit.com/*'] : [],
      optional_host_permissions: chromium ? ['<all_urls>'] : [],
      commands: {
        'save-link': { suggested_key: { default: 'Alt+Shift+L' }, description: 'Save page link' },
        'save-page': { suggested_key: { default: 'Alt+Shift+P' }, description: 'Save full page' },
      },
    };
  },
});
