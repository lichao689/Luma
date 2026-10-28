#!/usr/bin/env swift
import AppKit
import Foundation

// Build the app icon from the approved 1024+ source artwork.
//
// Usage:
//   swift tools/make_icon.swift [source_png]
//   swift tools/make_icon.swift --menu-bar-only
//
// Defaults:
//   source: OfficeWorkoutCoach/Resources/AppIcon-Source.png
//   outputs:
//     OfficeWorkoutCoach/Resources/AppIcon-1024.png
//     OfficeWorkoutCoach/Resources/AppIcon.icns
//     OfficeWorkoutCoach/Resources/AppMenuBarIconTemplate.png

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = Array(CommandLine.arguments.dropFirst())
let menuBarOnly = arguments.contains("--menu-bar-only")
let sourcePath = arguments.first { !$0.hasPrefix("--") }
    ?? "OfficeWorkoutCoach/Resources/AppIcon-Source.png"
let sourceURL = URL(fileURLWithPath: sourcePath, relativeTo: root).standardizedFileURL
let previewURL = root
    .appendingPathComponent("OfficeWorkoutCoach/Resources/AppIcon-1024.png")
let icnsURL = root.appendingPathComponent("OfficeWorkoutCoach/Resources/AppIcon.icns")
let menuBarIconURL = root.appendingPathComponent("OfficeWorkoutCoach/Resources/AppMenuBarIconTemplate.png")

let source: NSImage
if menuBarOnly {
    source = NSImage(size: NSSize(width: 1, height: 1))
} else if let loadedSource = NSImage(contentsOf: sourceURL) {
    source = loadedSource
} else {
    FileHandle.standardError.write("Missing source image: \(sourceURL.path)\n".data(using: .utf8)!)
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

if !menuBarOnly {
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

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("Failed to create menu-bar icon graphics context\n".data(using: .utf8)!)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    NSColor.black.setFill()

    func roundedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, radius: CGFloat) {
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: width, height: height),
            xRadius: radius,
            yRadius: radius
        ).fill()
    }

    // A menu-bar-specific silhouette. The app icon artwork has delicate
    // detail that collapses at 16 px, so this keeps the dumbbell bold and
    // horizontally readable in the status item.
    roundedRect(x: 4, y: 20, width: 13, height: 24, radius: 5)
    roundedRect(x: 16, y: 23, width: 8, height: 18, radius: 4)
    roundedRect(x: 23, y: 28, width: 18, height: 8, radius: 4)
    roundedRect(x: 40, y: 23, width: 8, height: 18, radius: 4)
    roundedRect(x: 47, y: 20, width: 13, height: 24, radius: 5)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render menu-bar icon PNG\n".data(using: .utf8)!)
        exit(1)
    }
    return png
}

try menuBarTemplateData().write(to: menuBarIconURL)

if !menuBarOnly {
    print("wrote \(previewURL.path)")
    print("wrote \(icnsURL.path)")
}
print("wrote \(menuBarIconURL.path)")
