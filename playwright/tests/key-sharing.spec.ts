/**
 * Togg KeySharing — web UX durumları (Docs/Playwright-KeySharing-plan.md K1–K6)
 *
 * Kural: yalnız dummy parametre kullanılır (repo Tests/KeySharingTests.swift sabitleri).
 * Gerçek VIN/token/kimlik malzemesi bu spec'te GEÇMEZ.
 * K7 (geçerli link UX'i) saha doğrulamasıdır — burada kodlanmaz.
 */
import { test, expect } from '@playwright/test';

/** Repo testlerinden alınmış dummy paylaşım parametreleri — gerçek veri değildir. */
const DUMMY = '?seId=AQIDBAUG&no=BwgJCgsM';
const DUMMY_SHORT = '?seId=AQID&no=BwgJCgsM';

test.describe('Togg KeySharing — web UX durumları', () => {
  /**
   * K1 (keşifte kanıtlandı): geçersiz seId → 4xx + boş render.
   * Beklenen UX: kullanıcıya içerik gösterilmez; sunucu çökmez (5xx yok).
   */
  test('K1: geçersiz seId ile link açıldığında içerik sunulmaz ve sunucu çökmez', async ({ page }) => {
    let navigated = false;
    try {
      const response = await page.goto(`/KeySharing${DUMMY_SHORT}`);
      navigated = true;
      // Render edilebildiyse bile 4xx olmalı; 5xx = sunucu çökmesi = test hatası
      expect(response!.status(), 'hata durumu 4xx olmalı (5xx yok)').toBeGreaterThanOrEqual(400);
      expect(response!.status()).toBeLessThan(500);
    } catch (error) {
      // Keşifte gözlenen UX durumu: ERR_HTTP_RESPONSE_CODE_FAILURE (boş render)
      expect(navigated, 'ya 4xx ile navigasyon tamamlanmalı ya da bilinen boş-render hatası gelmeli').toBe(false);
      expect(String(error), 'bilinen net hatası bekleniyor').toContain('ERR_HTTP_RESPONSE_CODE_FAILURE');
    }
  });

  /** K2 [plan: doğrulanmadı]: mükerrer seId → iOS parite ile 4xx beklenir. */
  test('K2: mükerrer seId parametresi reddedilir (iOS parite)', async ({ request }) => {
    const response = await request.get(`/KeySharing${DUMMY}&seId=AQIDBAUG`);
    expect(response.status(), 'mükerrer seId 4xx dönmeli (sunucu iOS paritesini uygular)').toBeGreaterThanOrEqual(400);
    expect(response.status()).toBeLessThan(500);
  });

  /** K3 [plan: doğrulanmadı]: fragment → yoksayılır ya da 4xx; 5xx ve route karışıklığı olmamalı. */
  test('K3: fragment içeren link kabul ya da reddedilir ama sunucu çökmez', async ({ request }) => {
    const response = await request.get(`/KeySharing${DUMMY}#fragment`);
    const status = response.status();
    expect(status, 'fragment 2xx (yoksayılmış) ya da 4xx olabilir; 5xx yasak').toBeLessThan(500);
  });

  /** K4 [plan: doğrulanmadı]: userinfo@ URL → reddedilir; 5xx yasak. */
  test('K4: userinfo içeren URL sunulmaz', async ({ request }) => {
    const response = await request.get(`https://user@share.togg.cloud/KeySharing${DUMMY}`);
    expect(response.status()).toBeGreaterThanOrEqual(400);
    expect(response.status()).toBeLessThan(500);
  });

  /** K5: sahte host ve TLS düşürme — iOS KeySharingTests paritesi. */
  test('K5: sahte host bağlantı kurulamaz ya da reddedilir', async ({ request }) => {
    // DNS çözülmezse request hata fırlatır → bu da geçerli reddetme UX'idir
    const response = await request
      .get(`https://togg.cloud.evil.example/KeySharing${DUMMY}`)
      .catch((error) => {
        test.expect(String(error).length).toBeGreaterThan(0);
        return null;
      });
    if (response !== null) {
      expect(response.status(), 'sahte host 200 İÇERİK döndürmemeli').not.toBe(200);
    }
  });

  test('K5b: TLS düşürülmemeli — http istek https yönlendirilmeli', async ({ request }) => {
    const response = await request.get(`http://share.togg.cloud/KeySharing${DUMMY}`);
    const finalUrl = response.url();
    const status = response.status();
    // Ya 3xx/4xx ile reddedilir ya da https'e yükseltilir; http içerik sunulmamalıdır
    const upgraded = new URL(finalUrl).protocol === 'https:';
    const rejected = status >= 300;
    expect(upgraded || rejected, 'http içerik sunulmamalı: https yükseltme ya da 3xx/4xx reddi').toBe(true);
  });

  /** K6: yanlış yol → 4xx; doğru yol yalnız /KeySharing. */
  test('K6: /notKeySharing yolu reddedilir', async ({ request }) => {
    const response = await request.get(`/notKeySharing${DUMMY}`);
    expect(response.status()).toBeGreaterThanOrEqual(400);
    expect(response.status()).toBeLessThan(500);
  });
});
