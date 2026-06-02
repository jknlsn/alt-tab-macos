import Cocoa

enum CommandSwitcherIconResolver {
    private struct CacheEntry {
        let image: CGImage?
        let timestamp: CFAbsoluteTime
    }

    private static var cache = [pid_t: CacheEntry]()
    private static let cacheTTL: CFTimeInterval = 10.0

    static func displayIcon(for application: Application) -> CGImage? {
        let now = CFAbsoluteTimeGetCurrent()
        if let cached = cache[application.pid], (now - cached.timestamp) < cacheTTL { return cached.image }
        let resolved = rasterizedIcon(resolveImage(for: application))
        cache[application.pid] = CacheEntry(image: resolved, timestamp: now)
        return resolved
    }

    static func clearCache() {
        cache.removeAll()
    }

    private static func resolveImage(for application: Application) -> NSImage {
        let fallback = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        if let bundleURL = application.bundleURL {
            if let values = try? bundleURL.resourceValues(forKeys: [.customIconKey]), let customIcon = values.customIcon { return customIcon }
            if let ghosttyIcon = ghosttyIcon(for: application) { return ghosttyIcon }
            let workspaceIcon = NSWorkspace.shared.icon(forFile: bundleURL.path)
            if !workspaceIcon.isValid { return application.runningApplication.icon ?? fallback }
            return workspaceIcon
        }
        return application.runningApplication.icon ?? fallback
    }

    private static func rasterizedIcon(_ icon: NSImage?) -> CGImage? {
        guard let icon else { return nil }
        let finalWidth = max(TilesPanel.maxPossibleAppIconSize.width, TilesPanel.maxPossibleAppIconSize.height)
        var proposedRect = CGRect(origin: .zero, size: NSSize(width: finalWidth, height: finalWidth))
        let hints: [NSImageRep.HintKey: NSNumber] = [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        guard let cgImage = icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: hints),
              let context = CGContext(data: nil, width: Int(finalWidth), height: Int(finalWidth), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little).rawValue) else { return nil }
        context.interpolationQuality = .high
        context.clear(CGRect(origin: .zero, size: NSSize(width: finalWidth, height: finalWidth)))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: finalWidth, height: finalWidth))
        return context.makeImage()
    }

    private static func ghosttyIcon(for application: Application) -> NSImage? {
        guard let bundleID = application.bundleIdentifier, bundleID.hasPrefix("com.mitchellh.ghostty"), let appBundleURL = application.bundleURL else { return nil }
        let pluginURL = appBundleURL.appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("PlugIns", isDirectory: true)
            .appendingPathComponent("DockTilePlugin.plugin", isDirectory: true)
        guard let pluginBundle = Bundle(url: pluginURL) else { return nil }
        for suite in [bundleID, "\(bundleID).debug"] {
            guard let defaults = UserDefaults(suiteName: suite), let data = defaults.data(forKey: "CustomGhosttyIcon2") else { continue }
            if let icon = parseGhosttyIcon(data, pluginBundle) { return icon }
        }
        return nil
    }

    private static func parseGhosttyIcon(_ data: Data, _ pluginBundle: Bundle) -> NSImage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let (caseName, payload) = object.first else { return nil }
        switch caseName {
            case "official": return nil
            case "blueprint": return pluginBundle.image(forResource: "BlueprintImage")
            case "chalkboard": return pluginBundle.image(forResource: "ChalkboardImage")
            case "glass": return pluginBundle.image(forResource: "GlassImage")
            case "holographic": return pluginBundle.image(forResource: "HolographicImage")
            case "microchip": return pluginBundle.image(forResource: "MicrochipImage")
            case "paper": return pluginBundle.image(forResource: "PaperImage")
            case "retro": return pluginBundle.image(forResource: "RetroImage")
            case "xray": return pluginBundle.image(forResource: "XrayImage")
            case "custom":
                guard let payload = payload as? [String: Any], let base64 = payload["_0"] as? String, let imageData = Data(base64Encoded: base64) else { return nil }
                return NSImage(data: imageData)
            case "customStyle":
                guard let payload = payload as? [String: Any],
                      let style = payload["_0"] as? [String: Any],
                      let ghostHex = style["ghostColor"] as? String,
                      let frame = style["frame"] as? String,
                      let screenHexes = style["screenColors"] as? [String],
                      let ghostColor = nsColor(hex: ghostHex) else { return nil }
                let screenColors = screenHexes.compactMap(nsColor(hex:))
                guard !screenColors.isEmpty else { return nil }
                return makeGhosttyCustomStyleIcon(pluginBundle: pluginBundle, screenColors: screenColors, ghostColor: ghostColor, frame: frame)
            default: return nil
        }
    }

    private static func makeGhosttyCustomStyleIcon(pluginBundle: Bundle, screenColors: [NSColor], ghostColor: NSColor, frame: String) -> NSImage? {
        guard let screen = pluginBundle.image(forResource: "CustomIconScreen"),
              let screenMask = pluginBundle.image(forResource: "CustomIconScreenMask"),
              let ghost = pluginBundle.image(forResource: "CustomIconGhost"),
              let crt = pluginBundle.image(forResource: "CustomIconCRT"),
              let gloss = pluginBundle.image(forResource: "CustomIconGloss") else { return nil }
        let baseName: String
        switch frame {
            case "aluminum": baseName = "CustomIconBaseAluminum"
            case "beige": baseName = "CustomIconBaseBeige"
            case "chrome": baseName = "CustomIconBaseChrome"
            default: baseName = "CustomIconBasePlastic"
        }
        guard let base = pluginBundle.image(forResource: baseName),
              let screenGradient = gradient(maskImage: screenMask, colors: screenColors),
              let tintedGhost = tintedImage(ghost, color: ghostColor) else { return nil }
        return combineImages([base, screen, screenGradient, ghost, tintedGhost, crt, gloss], blendingModes: [.normal, .normal, .color, .normal, .color, .overlay, .normal])
    }

    private static func combineImages(_ images: [NSImage], blendingModes: [CGBlendMode]) -> NSImage? {
        guard images.count == blendingModes.count, let firstImage = images.first else { return nil }
        let size = firstImage.size
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        for (index, image) in images.enumerated() {
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            context.setBlendMode(blendingModes[index])
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        guard let combined = context.makeImage() else { return nil }
        return NSImage(cgImage: combined, size: size)
    }

    private static func gradient(maskImage: NSImage, colors: [NSColor]) -> NSImage? {
        let size = maskImage.size
        guard let maskCGImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let cgColors = colors.compactMap(\.cgColor)
        guard !cgColors.isEmpty,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors as CFArray, locations: nil) else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        context.clip(to: rect, mask: maskCGImage)
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: size)
    }

    private static func tintedImage(_ image: NSImage, color: NSColor) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(origin: .zero, size: image.size)
        context.draw(cgImage, in: rect)
        context.setFillColor(color.cgColor)
        context.setBlendMode(.sourceAtop)
        context.fill(rect)
        guard let tinted = context.makeImage() else { return nil }
        return NSImage(cgImage: tinted, size: image.size)
    }

    private static func nsColor(hex: String) -> NSColor? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if cleaned.count == 8 {
            red = CGFloat((value >> 24) & 0xff) / 255
            green = CGFloat((value >> 16) & 0xff) / 255
            blue = CGFloat((value >> 8) & 0xff) / 255
            alpha = CGFloat(value & 0xff) / 255
        } else {
            red = CGFloat((value >> 16) & 0xff) / 255
            green = CGFloat((value >> 8) & 0xff) / 255
            blue = CGFloat(value & 0xff) / 255
            alpha = 1
        }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
