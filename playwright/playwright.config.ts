import { defineConfig, devices } from '@playwright/test';

/**
 * Toqdas Playwright — yalnız web'e bakan yüzeyler (bkz. Docs/Playwright-KeySharing-plan.md).
 * baseURL config'te; spec içinde mutlak URL sabitleme yoktur.
 */
export default defineConfig({
  testDir: './tests',
  outputDir: 'test-results',
  fullyParallel: true,
  retries: 1, // gerçek ağ hedefli; tek retry flaky overlay'i yutar, kök neden heal skill'indedir
  timeout: 30_000,
  expect: { timeout: 10_000 },
  reporter: [['list']],
  use: {
    baseURL: 'https://share.togg.cloud',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
