# Toqdas uygulama ikonu

## Kavram

Tek bir işaret: **"T" monogramı + anahtar deliği**.

- "T" → Toqdas/Togg.
- Gövdedeki anahtar deliği → dijital araç anahtarı; uygulamanın ne işe yaradığını
  metin olmadan anlatır.
- Tek vurgu rengi (cyan) yalnızca delikte kullanılır; 29–60 px boyutlarda bile
  okunur kalır.

## Renkler

| Öğe | Renk |
|---|---|
| Arka plan üst | `#05172E` |
| Arka plan alt | `#082B4F` |
| Işık (sol üst) | `#00A3FF` %30 |
| Glif | `#FAFDFF` |
| Anahtar deliği | `#00D6FA` |
| Teknoloji halkası | `#FFFFFF` %6 |

## Ölçüler (1024 taban)

- Üst bar: 480 × 132, köşe 52, alt kenar y=700
- Gövde: 144 genişlik, y=268…706, köşe 62
- Anahtar deliği: yarıçap 56, merkez (512, 548) + 48 × 150 yarık
- Glif, optik denge için 28 birim yukarı kaydırılır
- iOS'ta ince halka var; saatte yuvarlak maske ile çakışmaması için yok

## Dosyalar

- `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` (iOS, 1024)
- `Watch/AppIcon.icon/` (watchOS 26+, Icon Composer katmanlı ikon)
- `Watch/Assets.xcassets/AppIcon.appiconset/` (watchOS 9–25 için düz ikon)
- `Docs/Ikon/` — önizlemeler

Her iki hedefte de `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` ayarlıdır.

### watchOS 26 notu

watchOS 26, düz `appiconset` ikonunu uygulama ızgarasında göstermiyor;
Icon Composer `.icon` paketi gerekiyor (`AppIcon/Group`, `Color-1`,
`Gradient-1` katmanları). Bu yüzden `Watch/AppIcon.icon` eklendi:

- Tuval 1088×1088, `supported-platforms.circles = ["watchOS"]`.
- Arka plan `fill.automatic-gradient` (`#082B4F`) ile sistem tarafından üretilir.
- Tek katman: `Assets/T.png` — saydam zeminde beyaz "T" + cyan anahtar deliği.
- Eski `appiconset` geriye dönük uyumluluk için duruyor; aynı ada sahip
  oldukları için çakışmıyor.

Aynı `.icon` iOS 26'da Liquid Glass görünümü için de kullanılabilir; şimdilik
iOS'ta düz 1024 ikon korunuyor.

## Yeniden üretme

```sh
swift Tools/make_icon.swift /tmp/ikon
cp /tmp/ikon/ios-1024.png App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
cp /tmp/ikon/watch-1024.png Watch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
cp /tmp/ikon/watch-layer-1088.png Watch/AppIcon.icon/Assets/T.png
```

Çizim tamamen vektörel parametrelerle yapılır (`Tools/make_icon.swift`);
renk veya ölçü değişikliği tek dosyadan yönetilir.
