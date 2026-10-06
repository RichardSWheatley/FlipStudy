#!/usr/bin/env swift
// Render a family code as a QR card, using CoreImage — no packages to install.
// The code is printed under the QR on purpose: if a camera won't focus, or the
// image gets forwarded as a low-quality screenshot, the tester can still type it.
//
//   ./scripts/make-qr.swift FLIP-A7K2-9QX4 ~/Pictures/sam.png "Sam's iPhone"
import AppKit
import CoreImage

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make-qr.swift <CODE> <output.png> [caption]")
    exit(1)
}
let code = args[1]
let caption = args.count >= 4 ? args[3] : ""

guard let filter = CIFilter(name: "CIQRCodeGenerator") else { exit(1) }
filter.setValue(code.data(using: .utf8), forKey: "inputMessage")
// "H" keeps it readable even if the printout gets scuffed, creased or cropped.
filter.setValue("H", forKey: "inputCorrectionLevel")
guard let small = filter.outputImage else { exit(1) }

let qrSide: CGFloat = 640
let scale = qrSide / small.extent.width
let scaled = small.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let qrRep = NSCIImageRep(ciImage: scaled)
let qr = NSImage(size: qrRep.size)
qr.addRepresentation(qrRep)

let margin: CGFloat = 60
let textBlock: CGFloat = caption.isEmpty ? 110 : 170
let size = NSSize(width: qrSide + margin * 2, height: qrSide + margin * 2 + textBlock)

let canvas = NSImage(size: size)
canvas.lockFocus()
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()

qr.draw(in: NSRect(x: margin, y: textBlock + margin / 2, width: qrSide, height: qrSide))

func centered(_ text: String, font: NSFont, color: NSColor, y: CGFloat) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: style,
    ]
    (text as NSString).draw(
        in: NSRect(x: margin, y: y, width: qrSide, height: font.pointSize * 1.6),
        withAttributes: attrs)
}

if !caption.isEmpty {
    centered(caption, font: .systemFont(ofSize: 34, weight: .semibold),
             color: .black, y: textBlock - 46)
}
centered(code, font: .monospacedSystemFont(ofSize: 46, weight: .bold),
         color: .black, y: caption.isEmpty ? textBlock - 70 : textBlock - 112)
centered("Scan in FlipStudy → Settings → Enter Family Code",
         font: .systemFont(ofSize: 22), color: .secondaryLabelColor,
         y: caption.isEmpty ? 20 : 18)

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: (args[2] as NSString).expandingTildeInPath))
print("wrote \(args[2])")
