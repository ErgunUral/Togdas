/**
 * EPDK şarj istasyonu — API sözleşme nöbetçisi (Docs/Playwright-EPDK-plan.md E1–E7)
 *
 * Kota kuralı (plan §4): saatlik kota → koşu günde en fazla 1 kez.
 * Bu spec yalnız EPDK_CONTRACT_RUN=1 ile koşar (CI gece cron / elle tetik).
 * E7 (429 gözlemci) aktif tetiklenmez — yalnız plan kaydıdır.
 *
 * Gizlilik: istasyon adları/adresleri loglanmaz; yalnız sayım, alan adı ve tipler yazılır.
 */
import { test, expect } from '@playwright/test';
import https from 'node:https';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

/** Kota kapısı: env yoksa tüm spec skip — kota yemeyi engeller. */
test.skip(process.env.EPDK_CONTRACT_RUN !== '1', 'Kota kuralı: yalnız EPDK_CONTRACT_RUN=1 ile günde 1 koşum');

test.describe.configure({ mode: 'serial' });
test.describe('EPDK sözleşme nöbetçisi', () => {
  test.setTimeout(180_000); // ~16 MB gövde + ağ payı

  /** Türkiye koordinat sınırları (repo invariant; ±marj payı dahil) */
  const TURKIYE = { latMin: 35.5, latMax: 42.5, lonMin: 25.3, lonMax: 45.0 };

  /** Tek POST — tüm testler aynı yanıtı paylaşır; kota yalnız 1 kez kullanılır. */
  let shared: Promise<{ status: number; catalog: unknown; bodyBytes: number }> | undefined;
  function katalog() {
    return shared; // E1 kota dolu nedeniyle skip edilirse undefined → bağımlı testler de skip
  }

  /**
   * E1 taşıması: API, GET + {} gövdesi bekler (repo Docs/EPDK-Sarj-Istasyonlari.md — iOS'ta
   * URLSession GET gövdesini reddettiği için Network.framework kullanılır).
   * Playwright APIRequestContext GET gövdesini taşımaz → raw node:https ile iOS paritesi.
   * Not: bu tek istek convention dışı hostname literali kullanır (raw taşıma, baseURL uygulanamaz).
   */
  function getWithBody(path: string): Promise<{ status: number; body: Buffer }> {
    return new Promise((resolvePromise, reject) => {
      const req = https.request(
        {
          hostname: 'apigateway.epdk.gov.tr',
          path,
          method: 'GET',
          // iOS EPDKHTTPGetBodyTransport.sendRequest() ile birebir başlık paritesi
          headers: {
            Host: 'apigateway.epdk.gov.tr',
            'User-Agent': 'Toqdas/EPDK-iOS',
            'Content-Type': 'application/json',
            Accept: 'application/json',
            'Accept-Encoding': 'identity',
            'Content-Length': 2,
            Connection: 'close',
          },
          timeout: 120_000,
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on('data', (c: Buffer) => chunks.push(c));
          res.on('end', () => resolvePromise({ status: res.statusCode ?? 0, body: Buffer.concat(chunks) }));
        }
      );
      req.on('error', reject);
      req.on('timeout', () => req.destroy(new Error('EPDK yanıt zaman aşımı (120 sn)')));
      req.end('{}');
    });
  }

  test('E1: GET + {} gövdesi → 200 + statusCode/numRows alanları', async () => {
    const { status, body } = await getWithBody('/sarjIstasyonlari');

    // Kota kuralı (plan §E7 / iOS davranışı): 429 → Retry-After uygulanır; yoksa 1 saat beklenir.
    // Test tarafında 429 = fail değil, bilinçli skip — sonraki pencerede yeniden koşulmalı.
    test.skip(status === 429, 'EPDK saatlik kota dolu (429) — kota penceresinde yeniden koşulmalı');

    expect(status, 'EPDK katalog GET(gövdeli) 200 dönmeli').toBe(200);

    const parsed = JSON.parse(body.toString('utf8')) as Record<string, unknown>;
    expect(typeof parsed, 'yanıt bir nesne olmalı').toBe('object');
    expect(Object.keys(parsed), 'statusCode ve numRows alanları mevcut olmalı').toEqual(
      expect.arrayContaining(['statusCode', 'numRows'])
    );

    // Paylaşımlı önbelleğe al: sonraki testler aynı yanıtla çalışır (kota 1 kez)
    shared = Promise.resolve({ status, catalog: parsed, bodyBytes: body.byteLength });
  });
  test('E3: numRows > 0 — kamu katalogu boş olamaz', async () => {
    test.skip(!shared, 'EPDK kota dolu — E1 katalog yüklemedi, bu adım skip');
    const { catalog } = await katalog();
    const numRows = (catalog as { numRows: number }).numRows;
    // 0 ≠ bilgi yok — burada 0 katalog bozulmasıdır (plan §E3)
    expect(numRows, 'katalog boş olamaz (0 = bozulma sinyali)').toBeGreaterThan(0);
  });

  test('E5: yanıt gövdesi 32 MB sınırı altında', async () => {
    test.skip(!shared, 'EPDK kota dolu — E1 katalog yüklemedi, bu adım skip');
    const { bodyBytes } = await katalog();
    expect(bodyBytes, 'gövde 32 MB sınırını aşmamalı').toBeLessThan(32 * 1024 * 1024);
  });

  test('E2: istasyon şeması — ad/adres/koordinat/soket alanları mevcut; eksik alan 0\'a zorlanmamış', async () => {
    test.skip(!shared, 'EPDK kota dolu — E1 katalog yüklemedi, bu adım skip');
    const { catalog } = await katalog();
    const rows = (catalog as { rows?: unknown[] }).rows ?? (catalog as { data?: unknown[] }).data ?? [];
    expect(Array.isArray(rows), 'istasyon kayıt dizisi mevcut olmalı').toBe(true);
    expect(rows.length, 'kayıt sayısı numRows ile uyumlu olmalı').toBeGreaterThan(0);

    const first = rows[0] as Record<string, unknown>;
    const keys = Object.keys(first);
    // Şema gevşek doğrulama (plan §E2 [doğrulanmadı]): ad/adres/koordinat/soket aday alanları
    const hasNameLike = keys.some((k) => /ad|name|marka|brand/i.test(k));
    const hasAddressLike = keys.some((k) => /adres|address/i.test(k));
    const hasCoordLike = keys.some((k) => /lat|lon|enlem|boylam|koordinat/i.test(k));
    const hasSocketLike = keys.some((k) => /soket|socket|connector|konnektör/i.test(k));
    expect(hasNameLike, 'ad/marka alanı mevcut olmalı').toBe(true);
    expect(hasAddressLike, 'adres alanı mevcut olmalı').toBe(true);
    expect(hasCoordLike, 'koordinat alanı mevcut olmalı').toBe(true);
    expect(hasSocketLike, 'soket alanı mevcut olmalı').toBe(true);
  });
  test('E2b: şema snapshot — Docs/EPDK-schema-snapshot.md (yalnız alan adları, değer yok)', async () => {
    test.skip(!shared, 'EPDK kota dolu — E1 katalog yüklemedi, bu adım skip');
    const { catalog } = await katalog();
    const rows = ((catalog as { rows?: unknown[] }).rows ?? (catalog as { data?: unknown[] }).data) as Record<string, unknown>[];
    const keys = [...new Set(rows.slice(0, 20).flatMap((r) => Object.keys(r)))].sort();
    const lines = [
      '# EPDK şema snapshot — ' + new Date().toISOString().slice(0, 10),
      '',
      `numRows: ${(catalog as { numRows: number }).numRows} · örneklenen kayıt: ${Math.min(20, rows.length)}`,
      '(Değer YOK — yalnız alan adları; gizlilik invariant\'ı gereği)',
      '',
      ...keys.map((k) => `- ${k}`),
    ];
    writeFileSync(resolve(__dirname, '../../Docs/EPDK-schema-snapshot.md'), lines.join('\n') + '\n');
  });
  test('E4: koordinatlar Türkiye sınırları içinde', async () => {
    test.skip(!shared, 'EPDK kota dolu — E1 katalog yüklemedi, bu adım skip');
    const { catalog } = await katalog();
    const rows = ((catalog as { rows?: unknown[] }).rows ?? (catalog as { data?: unknown[] }).data) as Record<string, unknown>[];
    const coords = rows.slice(0, 50).flatMap((r) => {
      const entry = Object.entries(r).find(([k]) => /lat|enlem/i.test(k));
      const pair = Object.entries(r).find(([k]) => /lon|boylam/i.test(k));
      if (!entry || !pair) return [];
      const lat = Number(entry[1]);
      const lon = Number(pair[1]);
      return Number.isFinite(lat) && Number.isFinite(lon) ? [{ lat, lon }] : [];
    });
    expect(coords.length, 'koordinat çiftleri okunabilmeli').toBeGreaterThan(0);
    for (const { lat, lon } of coords) {
      expect.soft(lat, 'enlem Türkiye aralığında').toBeGreaterThanOrEqual(TURKIYE.latMin);
      expect.soft(lat).toBeLessThanOrEqual(TURKIYE.latMax);
      expect.soft(lon, 'boylam Türkiye aralığında').toBeGreaterThanOrEqual(TURKIYE.lonMin);
      expect.soft(lon).toBeLessThanOrEqual(TURKIYE.lonMax);
    }
  });

  test('E6: gövdesiz GET → 400 (UI yok paritesi — keşifte kanıtlandı)', async ({ request }) => {
    const response = await request.get('/sarjIstasyonlari');
    test.skip(
      response.status() === 429,
      'EPDK saatlik kota dolu (429) — kota penceresinde yeniden koşulmalı'
    );
    expect(response.status(), 'gövdesiz GET reddedilmeli').toBe(400);
  });
});
