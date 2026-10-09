#!/usr/bin/env swift
// Builds FlipStudy's app icons as Liquid Glass (Icon Composer) documents: two
// glass cards, a "?" and a pair of sparkles over a two-tone background, once
// per colour kids can pick in Settings. iOS adds the glass, the light and the
// dark, clear and tinted versions itself. Run from the repo root:
//
//   swift scripts/make-app-icons.swift
//
// Writes FlipStudy/AppIcon.icon (Classic) and FlipStudy/AppIcon-<Name>.icon,
// plus a preview of each into $TMPDIR/flipstudy-icon-previews/ (rendered by
// Icon Composer's own ictool, so it shows exactly what iOS will draw).

import AppKit
import CoreGraphics
import CoreText

struct Theme {
    let name: String      // "" for the primary icon
    let top: (Double, Double, Double)
    let bottom: (Double, Double, Double)
    var whiteSparkles = false   // on warm backgrounds a yellow sparkle disappears
}

/// The icon colours: brighter, two-hue versions of AppTheme in
/// Shared/Palette.swift, in Display P3 so they glow on the phone.
let themes: [Theme] = [
    Theme(name: "", top: (0.33, 0.50, 1.00), bottom: (0.48, 0.22, 0.94)),
    Theme(name: "Ocean", top: (0.20, 0.80, 1.00), bottom: (0.10, 0.38, 0.95)),
    Theme(name: "Grape", top: (0.80, 0.56, 1.00), bottom: (0.45, 0.20, 0.92)),
    Theme(name: "Berry", top: (1.00, 0.46, 0.44), bottom: (0.88, 0.10, 0.42)),
    Theme(name: "Tangerine", top: (1.00, 0.76, 0.24), bottom: (1.00, 0.36, 0.12), whiteSparkles: true),
    Theme(name: "Sunshine", top: (1.00, 0.88, 0.28), bottom: (1.00, 0.58, 0.04), whiteSparkles: true),
    Theme(name: "Lime", top: (0.72, 0.92, 0.24), bottom: (0.18, 0.64, 0.26), whiteSparkles: true),
    Theme(name: "Mint", top: (0.36, 0.95, 0.80), bottom: (0.00, 0.58, 0.54)),
    Theme(name: "Bubblegum", top: (1.00, 0.62, 0.80), bottom: (0.90, 0.18, 0.60)),
]

let size = 1024
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx)
    return ctx.makeImage()!
}

func colour(_ c: (Double, Double, Double)) -> CGColor {
    CGColor(colorSpace: space, components: [c.0, c.1, c.2, 1])!
}

func card(_ ctx: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, degrees: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: height * 0.16, cornerHeight: height * 0.16, transform: nil))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
}

func questionMark(_ ctx: CGContext, center: CGPoint, degrees: CGFloat, colour: CGColor) {
    let base = NSFont.systemFont(ofSize: 300, weight: .black)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: 300) ?? base
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "?", attributes: [.font: font, .foregroundColor: colour]))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

/// A four-pointed star with pinched, curved sides.
func sparkle(_ ctx: CGContext, center c: CGPoint, radius r: CGFloat, colour: CGColor) {
    let k: CGFloat = 0.16
    let path = CGMutablePath()
    path.move(to: CGPoint(x: c.x, y: c.y + r))
    path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * k, y: c.y + r * k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * k, y: c.y - r * k))
    path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * k, y: c.y - r * k))
    path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * k, y: c.y + r * k))
    ctx.addPath(path)
    ctx.setFillColor(colour)
    ctx.fillPath()
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

func p3(_ c: (Double, Double, Double)) -> String {
    String(format: "display-p3:%.5f,%.5f,%.5f,1.00000", c.0, c.1, c.2)
}

/// Layers, front to back. Each group is a separate sheet of glass.
func iconJSON(_ theme: Theme) -> String {
    """
    {
      "fill" : {
        "linear-gradient" : [
          "\(p3(theme.top))",
          "\(p3(theme.bottom))"
        ]
      },
      "groups" : [
        {
          "layers" : [
            { "image-name" : "sparkles.png", "name" : "sparkles", "glass" : true }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
          "translucency" : { "enabled" : false, "value" : 0.5 }
        },
        {
          "layers" : [
            { "image-name" : "question.png", "name" : "question", "glass" : false },
            { "image-name" : "front-card.png", "name" : "front-card", "glass" : true }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.55 },
          "translucency" : { "enabled" : true, "value" : 0.15 }
        },
        {
          "layers" : [
            { "image-name" : "back-card.png", "name" : "back-card", "glass" : true, "opacity" : 0.55 }
          ],
          "shadow" : { "kind" : "neutral", "opacity" : 0.4 },
          "translucency" : { "enabled" : true, "value" : 0.6 }
        }
      ],
      "supported-platforms" : {
        "squares" : [ "iOS" ]
      }
    }

    """
}

let root = URL(fileURLWithPath: "FlipStudy")
guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Assets.xcassets").path) else {
    FileHandle.standardError.write("Run this from the repo root.\n".data(using: .utf8)!)
    exit(1)
}
let previews = FileManager.default.temporaryDirectory.appendingPathComponent("flipstudy-icon-previews")
try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
let ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"

// Card positions (Core Graphics: y=0 at the bottom). Shared by every colour.
let front = CGPoint(x: 536, y: 440)
for theme in themes {
    let iconName = theme.name.isEmpty ? "AppIcon" : "AppIcon-\(theme.name)"
    let bundle = root.appendingPathComponent("\(iconName).icon")
    let assets = bundle.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: bundle)
    try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

    let sparkleColour = theme.whiteSparkles ? CGColor(gray: 1, alpha: 1) : colour((1.00, 0.86, 0.30))
    try writePNG(canvas { card($0, center: CGPoint(x: 432, y: 596), width: 560, height: 390, degrees: -12) },
                 to: assets.appendingPathComponent("back-card.png"))
    try writePNG(canvas { card($0, center: front, width: 600, height: 416, degrees: 7) },
                 to: assets.appendingPathComponent("front-card.png"))
    try writePNG(canvas { questionMark($0, center: front, degrees: 7, colour: colour(theme.bottom)) },
                 to: assets.appendingPathComponent("question.png"))
    try writePNG(canvas {
        sparkle($0, center: CGPoint(x: 806, y: 770), radius: 118, colour: sparkleColour)
        sparkle($0, center: CGPoint(x: 676, y: 884), radius: 46, colour: sparkleColour)
    }, to: assets.appendingPathComponent("sparkles.png"))
    try iconJSON(theme).write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)

    let preview = Process()
    preview.executableURL = URL(fileURLWithPath: ictool)
    preview.arguments = [bundle.path, "--export-image",
                         "--output-file", previews.appendingPathComponent("\(theme.name.isEmpty ? "Classic" : theme.name).png").path,
                         "--platform", "iOS", "--rendition", "Default",
                         "--width", "1024", "--height", "1024", "--scale", "1"]
    preview.standardOutput = FileHandle.nullDevice
    try preview.run()
    preview.waitUntilExit()
    print(iconName)
}
print("Previews: \(previews.path)")
