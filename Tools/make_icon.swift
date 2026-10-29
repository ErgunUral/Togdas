import AppKit
import CoreGraphics
import Foundation

/// Toqdas uygulama ikonu.
///
/// Kavram: "T" monogramı + anahtar deliği. Gövdedeki delik, dijital anahtarın
/// kilidi açtığını anlatır; tek renk vurgu (cyan) küçük boyutlarda da okunur.
/// Aynı çizim iOS (kare) ve watchOS (yuvarlak maske) için ayrı ölçeklenir.
enum IconRenderer {
    static func render(size: CGFloat, watch: Bool, transparent: Bool = false) -> NSBitmapImageRep {
        let px = Int(size)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext

        let s = size
        func p(_ v: CGFloat) -> CGFloat { v / 1024.0 * s }

        // Arka plan: gece mavisi -> derin lacivert (çapraz)
        let colors = [
            CGColor(red: 0.02, green: 0.09, blue: 0.18, alpha: 1),
            CGColor(red: 0.03, green: 0.17, blue: 0.31, alpha: 1)
        ] as CFArray
        if transparent {
            // Icon Composer katmanı: yalnızca glif, arka plan .icon "fill"inden gelir.
            cg.clear(CGRect(x: 0, y: 0, width: s, height: s))
        } else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: s),
                                  end: CGPoint(x: s, y: 0),
                                  options: [])
        }

        // Sol üstte marka mavisi ışık
        let glow = [
            CGColor(red: 0.0, green: 0.64, blue: 1.0, alpha: watch ? 0.36 : 0.30),
            CGColor(red: 0.0, green: 0.64, blue: 1.0, alpha: 0.0)
        ] as CFArray
        if !transparent, let radial = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: glow, locations: [0, 1]) {
            cg.drawRadialGradient(radial,
                                  startCenter: CGPoint(x: s * 0.18, y: s * 0.86), startRadius: 0,
                                  endCenter: CGPoint(x: s * 0.18, y: s * 0.86), endRadius: s * 0.80,
                                  options: [])
        }

        // İnce teknoloji halkası (saatte yuvarlak maskeyle çakışmasın diye yok)
        if !watch && !transparent {
            cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.06))
            cg.setLineWidth(p(6))
            cg.strokeEllipse(in: CGRect(x: p(96), y: p(96), width: p(832), height: p(832)))
        }

        // Glif ölçeği: saatte yuva içinde daha dolu görünmesi için hafif büyük
        let scale: CGFloat = watch ? 1.06 : 1.0
        let center = CGPoint(x: s / 2, y: s / 2)
        cg.translateBy(x: center.x, y: center.y)
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -center.x, y: -center.y)

        // Optik ortalama: glif gövdesi 28 birim yukarı kaydırılır
        let dy = p(28)
        func y(_ v: CGFloat) -> CGFloat { p(v) - dy }

        let white = CGColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1)

        if !transparent {
            cg.setShadow(offset: CGSize(width: 0, height: p(-16)),
                         blur: p(44),
                         color: CGColor(red: 0, green: 0.05, blue: 0.10, alpha: 0.50))
        }

        // T üst barı
        let barWidth = p(480)
        let barHeight = p(132)
        let barBottom = y(700)
        cg.setFillColor(white)
        cg.addPath(CGPath(roundedRect: CGRect(x: p(512) - barWidth / 2, y: barBottom,
                                              width: barWidth, height: barHeight),
                          cornerWidth: p(52), cornerHeight: p(52), transform: nil))
        cg.fillPath()

        // T gövdesi
        let stemWidth = p(144)
        let stemBottom = y(268)
        cg.addPath(CGPath(roundedRect: CGRect(x: p(512) - stemWidth / 2, y: stemBottom,
                                              width: stemWidth, height: barBottom - stemBottom + p(6)),
                          cornerWidth: p(62), cornerHeight: p(62), transform: nil))
        cg.fillPath()

        // Anahtar deliği: dijital kimlik vurgusu
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.setFillColor(CGColor(red: 0.0, green: 0.84, blue: 0.98, alpha: 1))
        let holeRadius = p(56)
        let holeCenter = CGPoint(x: p(512), y: y(548))
        cg.fillEllipse(in: CGRect(x: holeCenter.x - holeRadius, y: holeCenter.y - holeRadius,
                                  width: holeRadius * 2, height: holeRadius * 2))
        let slit = CGRect(x: p(512) - p(24), y: y(360), width: p(48), height: p(150))
        cg.addPath(CGPath(roundedRect: slit, cornerWidth: p(24), cornerHeight: p(24), transform: nil))
        cg.fillPath()

        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func write(size: CGFloat, watch: Bool, transparent: Bool = false, to path: String) throws {
        let rep = render(size: size, watch: watch, transparent: transparent)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "icon", code: 1)
        }
        try data.write(to: URL(fileURLWithPath: path))
    }
}

let args = CommandLine.arguments
let output = args.count > 1 ? args[1] : "."
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
try IconRenderer.write(size: 1024, watch: false, to: output + "/ios-1024.png")
try IconRenderer.write(size: 1024, watch: true, to: output + "/watch-1024.png")

// watchOS 26 Icon Composer katmanı: 1088 kare, yalnızca glif (arka plan "fill").
try IconRenderer.write(size: 1088, watch: true, transparent: true,
                       to: output + "/watch-layer-1088.png")

// watchOS klasik set: küçük boyutlar doğrudan vektörden üretilir (daha keskin).
if args.contains("--watch-sizes") {
    for px in [48, 55, 58, 80, 87, 88, 100, 172, 196, 216, 234, 258] {
        try IconRenderer.write(size: CGFloat(px), watch: true,
                               to: output + "/watch-\(px).png")
    }
}

print("ok: \(output)")
