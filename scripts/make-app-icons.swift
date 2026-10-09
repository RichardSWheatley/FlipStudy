#!/usr/bin/env swift
// Draws FlipStudy's alternate app icons — the same two-card "?" design as the
// primary icon, once per colour kids can pick in Settings. Run from the repo
// root after changing a colour in Shared/Palette.swift:
//
//   swift scripts/make-app-icons.swift
//
// Writes FlipStudy/Assets.xcassets/AppIcon-<Name>.appiconset for each colour.
// Icons are opaque (no alpha channel): the App Store rejects transparent ones.

import AppKit
import CoreGraphics
import CoreText

/// Must match DeckPalette in Shared/Palette.swift.
let colours: [(name: String, top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat))] = [
    ("Ocean", (0.30, 0.67, 0.97), (0.11, 0.44, 0.86)),
    ("Grape", (0.69, 0.59, 0.99), (0.44, 0.28, 0.91)),
    ("Berry", (1.00, 0.42, 0.48), (0.90, 0.18, 0.36)),
    ("Tangerine", (1.00, 0.66, 0.30), (0.98, 0.42, 0.13)),
    ("Sunshine", (1.00, 0.80, 0.20), (0.96, 0.58, 0.00)),
    ("Lime", (0.55, 0.83, 0.27), (0.22, 0.62, 0.24)),
    ("Mint", (0.22, 0.85, 0.66), (0.03, 0.60, 0.47)),
    ("Bubblegum", (0.97, 0.51, 0.67), (0.84, 0.20, 0.42)),
]

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func colour(_ c: (CGFloat, CGFloat, CGFloat), alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [c.0, c.1, c.2, alpha])!
}

func card(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, degrees: CGFloat, fill: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    let path = CGPath(roundedRect: rect, cornerWidth: height * 0.14, cornerHeight: height * 0.14, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: CGColor(gray: 0, alpha: 0.18))
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.restoreGState()
}

func roundedHeavyFont(size: CGFloat) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
}

func drawIcon(top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let s = CGFloat(size)

    // Background: lighter at the top left, deeper at the bottom right.
    let gradient = CGGradient(colorsSpace: space, colors: [colour(top), colour(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // The card behind, see-through; then the card in front with its "?".
    // (Core Graphics puts y=0 at the bottom.)
    card(ctx, center: CGPoint(x: 450, y: 620), width: 600, height: 410, degrees: -11, fill: CGColor(gray: 1, alpha: 0.38))
    let front = CGPoint(x: 548, y: 452)
    card(ctx, center: front, width: 620, height: 430, degrees: 6, fill: CGColor(gray: 1, alpha: 1))

    let attributes: [NSAttributedString.Key: Any] = [
        .font: roundedHeavyFont(size: 330),
        .foregroundColor: colour(bottom),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "?", attributes: attributes))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.translateBy(x: front.x, y: front.y)
    ctx.rotate(by: 6 * .pi / 180)
    ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    return ctx.makeImage()!
}

let assets = URL(fileURLWithPath: "FlipStudy/Assets.xcassets")
guard FileManager.default.fileExists(atPath: assets.path) else {
    FileHandle.standardError.write("Run this from the repo root.\n".data(using: .utf8)!)
    exit(1)
}

let contents = """
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

for c in colours {
    let folder = assets.appendingPathComponent("AppIcon-\(c.name).appiconset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let image = drawIcon(top: c.top, bottom: c.bottom)
    let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try png.write(to: folder.appendingPathComponent("AppIcon.png"))
    try contents.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("AppIcon-\(c.name)")
}
