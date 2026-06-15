#!/usr/bin/env swift
import AppKit
import Foundation

// Build the app icon from the approved 1024+ source artwork.
//
// Usage:
//   swift tools/make_icon.swift [source_png]
//
// Defaults:
//   source: OfficeWorkoutCoach/Resources/AppIcon-Source.png
//   outputs:
//     OfficeWorkoutCoach/Resources/AppIcon-1024.png
//     OfficeWorkoutCoach/Resources/AppIcon.icns
//     OfficeWorkoutCoach/Resources/AppMenuBarIconTemplate.png

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourcePath = CommandLine.arguments.dropFirst().first
    ?? "OfficeWorkoutCoach/Resources/AppIcon-Source.png"
let sourceURL = URL(fileURLWithPath: sourcePath, relativeTo: root).standardizedFileURL
let previewURL = root
    .appendingPathComponent("OfficeWorkoutCoach/Resources/AppIcon-1024.png")
let icnsURL = root.appendingPathComponent("OfficeWorkoutCoach/Resources/AppIcon.icns")
let menuBarIconURL = root.appendingPathComponent("OfficeWorkoutCoach/Resources/AppMenuBarIconTemplate.png")

guard let source = NSImage(contentsOf: sourceURL) else {
    FileHandle.standardError.write("Missing source image: \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

guard let sourceTiff = source.tiffRepresentation,
      let sourceRep = NSBitmapImageRep(data: sourceTiff) else {
    FileHandle.standardError.write("Unable to read source pixels: \(sourceURL.path)\n".data(using: .utf8)!)
    exit(1)
}

func pngData(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("Failed to allocate \(size)x\(size) bitmap\n".data(using: .utf8)!)
        exit(1)
    }

    let context = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let canvasSize = NSSize(width: size, height: size)
    let rect = NSRect(origin: .zero, size: canvasSize)
    NSColor.clear.setFill()
    rect.fill()

    // The approved raster source has square black corners. Reclip it to the
    // macOS icon rounded rectangle so the final PNG/ICNS carries clean alpha.
    let radius = CGFloat(size) * 0.2237
    let clip = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    clip.addClip()
    source.draw(in: rect,
                from: NSRect(origin: .zero, size: source.size),
                operation: .sourceOver,
                fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(size)x\(size) PNG\n".data(using: .utf8)!)
        exit(1)
    }
    return png
}

try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
try pngData(size: 1024).write(to: previewURL)

let tempIconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("luma-app-icon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: tempIconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempIconset) }

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, size) in iconFiles {
    try pngData(size: size).write(to: tempIconset.appendingPathComponent(filename))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(process.terminationStatus)\n".data(using: .utf8)!)
    exit(Int32(process.terminationStatus))
}

func menuBarTemplateData(size: Int = 64) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        FileHandle.standardError.write("Failed to allocate menu-bar icon bitmap\n".data(using: .utf8)!)
        exit(1)
    }

    guard let bitmap = rep.bitmapData else {
        FileHandle.standardError.write("Missing menu-bar icon bitmap storage\n".data(using: .utf8)!)
        exit(1)
    }

    for index in 0..<(rep.bytesPerRow * size) {
        bitmap[index] = 0
    }

    let sourceWidth = sourceRep.pixelsWide
    let sourceHeight = sourceRep.pixelsHigh

    for y in 0..<size {
        for x in 0..<size {
            let sx = min(sourceWidth - 1, max(0, Int((Double(x) + 0.5) * Double(sourceWidth) / Double(size))))
            let sy = min(sourceHeight - 1, max(0, Int((Double(y) + 0.5) * Double(sourceHeight) / Double(size))))
            guard let sourceColor = sourceRep.colorAt(x: sx, y: sy)?.usingColorSpace(.deviceRGB) else {
                continue
            }

            let red = sourceColor.redComponent
            let green = sourceColor.greenComponent
            let blue = sourceColor.blueComponent
            let minimum = min(red, min(green, blue))
            let maximum = max(red, max(green, blue))
            let neutral = max(0, 1 - (maximum - minimum) * 5)
            let bright = max(0, min(1, (minimum - 0.55) / 0.38))
            let alpha = bright * neutral * sourceColor.alphaComponent

            if alpha > 0.01 {
                let index = y * rep.bytesPerRow + x * 4
                bitmap[index] = 0
                bitmap[index + 1] = 0
                bitmap[index + 2] = 0
                bitmap[index + 3] = UInt8(max(0, min(255, Int(alpha * 255))))
            }
        }
    }

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render menu-bar icon PNG\n".data(using: .utf8)!)
        exit(1)
    }
    return png
}

try menuBarTemplateData().write(to: menuBarIconURL)

print("wrote \(previewURL.path)")
print("wrote \(icnsURL.path)")
print("wrote \(menuBarIconURL.path)")
