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
  projects: [
    // KeySharing web UX yüzeyi — EPDK spec'ini dışla (farklı baseURL)
    { name: 'chromium', use: { ...devices['Desktop Chrome'] }, testIgnore: '**/epdk-contract.spec.ts' },
    // EPDK API sözleşme nöbetçisi — Docs/Playwright-EPDK-plan.md
    { name: 'epdk', use: { ...devices['Desktop Chrome'], baseURL: 'https://apigateway.epdk.gov.tr' }, testMatch: '**/epdk-contract.spec.ts' },
  ],
});
