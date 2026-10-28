#!/usr/bin/env swift
import AppKit
import Foundation

// Generate the app icon and the menu-bar template icon procedurally.
//
// Usage:
//   swift tools/make_icon.swift                    # write the resource files
//   swift tools/make_icon.swift --preview          # write preview PNGs to /tmp
//   swift tools/make_icon.swift --menu-bar-only    # only the status-item template
//
// Outputs:
//   OfficeWorkoutCoach/Resources/AppIcon-1024.png
//   OfficeWorkoutCoach/Resources/AppIcon.icns
//   OfficeWorkoutCoach/Resources/AppMenuBarIconTemplate.png
//
// Design notes
// ------------
// * The app icon follows Apple's macOS grid: an 824x824 rounded square centred
//   on a 1024 canvas. Filling the whole canvas (what the old raster source did)
//   makes the icon read larger and heavier than every native app in the Dock.
// * Corners are a superellipse (Apple's "continuous" corner), not a circular
//   rounded rect, so the silhouette matches system icons.
// * Everything is drawn as vectors at each output size, so 16px stays crisp
//   instead of being a blurry downscale of a 1024 raster.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let arguments = Array(CommandLine.arguments.dropFirst())
let menuBarOnly = arguments.contains("--menu-bar-only")
let previewOnly = arguments.contains("--preview")

let resourcesDir = root.appendingPathComponent("OfficeWorkoutCoach/Resources")
let previewURL = resourcesDir.appendingPathComponent("AppIcon-1024.png")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
let menuBarIconURL = resourcesDir.appendingPathComponent("AppMenuBarIconTemplate.png")

// MARK: - Canvas geometry (1024pt design space)

let canvas: CGFloat = 1024
let plateInset: CGFloat = 100            // Apple grid: 824 content box
let contentSide: CGFloat = canvas - plateInset * 2
let cornerExponent: CGFloat = 4.8        // superellipse, approximates the squircle

func squirclePath(in rect: NSRect, exponent: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let a = rect.width / 2
    let b = rect.height / 2
    let cx = rect.midX
    let cy = rect.midY
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let x = cx + a * copysign(pow(abs(ct), 2 / exponent), ct)
        let y = cy + b * copysign(pow(abs(st), 2 / exponent), st)
        if step == 0 { path.move(to: NSPoint(x: x, y: y)) }
        else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

// MARK: - Dumbbell mark
//
// Three rounded bars: two plates and a grip. Deliberately simple — the mark has
// to survive being rendered at 16px, so no stepped plates and no inner detail.

struct Bar {
    let rect: NSRect
    let radius: CGFloat
}

let plateHeight: CGFloat = 258
let plateWidth: CGFloat = 142
let gripHeight: CGFloat = 86
let markWidth: CGFloat = 552

func dumbbellBars(centerY: CGFloat, scale: CGFloat = 1) -> [Bar] {
    let halfMark = markWidth * scale / 2
    let pw = plateWidth * scale
    let ph = plateHeight * scale
    let gh = gripHeight * scale
    let gap: CGFloat = 0   // grip meets the plates so the mark reads as one object

    let left = Bar(
        rect: NSRect(x: canvas / 2 - halfMark, y: centerY - ph / 2, width: pw, height: ph),
        radius: pw * 0.30
    )
    let right = Bar(
        rect: NSRect(x: canvas / 2 + halfMark - pw, y: centerY - ph / 2, width: pw, height: ph),
        radius: pw * 0.30
    )
    let grip = Bar(
        rect: NSRect(
            x: canvas / 2 - halfMark + pw + gap,
            y: centerY - gh / 2,
            width: markWidth * scale - (pw + gap) * 2,
            height: gh
        ),
        radius: gh * 0.5
    )
    return [left, grip, right]
}

// MARK: - Icon rendering

func makeBitmap(size: Int) -> NSBitmapImageRep {
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
    rep.size = NSSize(width: size, height: size)
    return rep
}

func drawIcon(in rep: NSBitmapImageRep) {
    let pixelSize = CGFloat(rep.pixelsWide)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.scaleBy(x: pixelSize / canvas, y: pixelSize / canvas)

    let full = NSRect(x: 0, y: 0, width: canvas, height: canvas)
    NSColor.clear.setFill()
    full.fill()

    let content = NSRect(x: plateInset, y: plateInset, width: contentSide, height: contentSide)
    let squircle = squirclePath(in: content, exponent: cornerExponent)

    cg.saveGState()
    squircle.addClip()

    // Base gradient: bright top, deep bottom. Native icons are rarely a single
    // flat hue — the vertical ramp is what gives the tile volume.
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.239, green: 0.478, blue: 0.980, alpha: 1),   // #3D7AFA
        ending: NSColor(srgbRed: 0.078, green: 0.196, blue: 0.647, alpha: 1)     // #1432A5
    )!
    gradient.draw(in: content, angle: -90)

    // Soft specular highlight near the top edge.
    let glowColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22)
    let glowCenter = NSPoint(x: canvas / 2, y: canvas * 0.74)
    let glow = NSGradient(colors: [glowColor, glowColor.withAlphaComponent(0)])!
    glow.draw(fromCenter: glowCenter, radius: 0,
              toCenter: glowCenter, radius: contentSide * 0.55,
              options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])

    cg.restoreGState()

    // Mark: flat white, optically centred.
    NSColor(srgbRed: 0.99, green: 0.995, blue: 1.0, alpha: 1).setFill()
    for bar in dumbbellBars(centerY: canvas * 0.5) {
        NSBezierPath(roundedRect: bar.rect, xRadius: bar.radius, yRadius: bar.radius).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
}

func iconPNG(size: Int) -> Data {
    let rep = makeBitmap(size: size)
    drawIcon(in: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(size)px PNG\n".data(using: .utf8)!)
        exit(1)
    }
    return png
}

// MARK: - Menu-bar template
//
// Rendered at 72px (18pt @4x) so the status item has headroom on every display
// scale. Three shapes only: at 16pt the old two-tier plates turned to mush.

func menuBarTemplate(size: Int = 72) -> Data {
    let rep = makeBitmap(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.scaleBy(x: CGFloat(size) / 64, y: CGFloat(size) / 64)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 64, height: 64).fill()

    NSColor.black.setFill()
    func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: w, height: h),
            xRadius: r, yRadius: r
        ).fill()
    }
    // Plates are 28 tall on a 64 grid so the silhouette stays solid once the
    // status item scales it down to 18pt; the grip is 13 tall (~46%).
    bar(2, 17, 15, 30, 4.5)
    bar(17, 26.5, 30, 11, 5.5)
    bar(47, 17, 15, 30, 4.5)

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    return png
}

// MARK: - Write

try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

if previewOnly {
    let out = FileManager.default.temporaryDirectory
    for px in [512, 128] {
        let url = out.appendingPathComponent("luma-icon-\(px).png")
        try iconPNG(size: px).write(to: url)
        print("wrote \(url.path)")
    }
    let mb = out.appendingPathComponent("luma-menubar.png")
    try menuBarTemplate().write(to: mb)
    print("wrote \(mb.path)")
    exit(0)
}

if !menuBarOnly {
    try iconPNG(size: 1024).write(to: previewURL)

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
        try iconPNG(size: size).write(to: tempIconset.appendingPathComponent(filename))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write("iconutil failed (\(process.terminationStatus))\n".data(using: .utf8)!)
        exit(Int32(process.terminationStatus))
    }
}

try menuBarTemplate().write(to: menuBarIconURL)

if !menuBarOnly {
    print("wrote \(previewURL.path)")
    print("wrote \(icnsURL.path)")
}
print("wrote \(menuBarIconURL.path)")
