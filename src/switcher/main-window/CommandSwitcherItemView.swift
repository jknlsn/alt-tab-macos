import Cocoa

final class CommandSwitcherItemView: FlippedView {
    static let labelMaxWidth = CGFloat(440)
    static let labelTopSpacing = CGFloat(8)
    static let labelAreaHeight = CGFloat(30)
    private static var iconSize: NSSize { NSSize(width: Appearance.iconSize, height: Appearance.iconSize) }

    var window_: Window?
    let appIcon = LightImageLayer()
    let dockLabelIcon = TileFontIconView(badgeSize: TileFontIconView.badgeBaseSize(forIconSize: NSSize(width: Appearance.iconSize, height: Appearance.iconSize).width))
    let label = TileTitleView(font: Appearance.font)
    private var highlightView: SelectionEffectView?
    private var fullTitle = ""
    private var fullTitleWidth = CGFloat(0)

    var indexInRecycledViews = 0

    override var canBecomeKeyView: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        layer!.masksToBounds = false
        appIcon.contentsGravity = .resizeAspect
        appIcon.applyShadow(nil)
        layer!.addSublayer(appIcon)
        dockLabelIcon.shadow = TileView.makeShadow(Appearance.imagesShadowColor)
        addSubview(dockLabelIcon)
        addSubview(label)
        label.alignment = .center
        label.isHidden = true
        label.fixHeight()
    }

    func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat) {
        indexInRecycledViews = index
        window_ = element
        fullTitle = getAppOrAndWindowTitle(element)
        label.stringValue = fullTitle
        fullTitleWidth = label.cell!.cellSize.width
        label.updateTruncationModeIfNeeded()
        label.toolTip = nil
        appIcon.updateContents(.cgImage(CommandSwitcherStyle.displayIcon(for: element)), Self.iconSize)
        updateDockLabelIcon(element.dockLabel)
        setAccessibilityLabel(fullTitle)
        setAccessibilityHelp([element.application.localizedName, CommandSwitcherStyle.badgeAccessibilityText(element.dockLabel)].compactMap { $0 }.joined(separator: " - "))
        updateFrame(newHeight)
        updateLayout()
    }

    private func updateFrame(_ newHeight: CGFloat) {
        let tileSize = Appearance.commandSwitcherTileSize
        frame.size = NSSize(width: tileSize, height: newHeight)
    }

    private func updateLayout() {
        let tileSize = Appearance.commandSwitcherTileSize
        appIcon.frame.size = Self.iconSize
        appIcon.frame.origin = CGPoint(x: ((tileSize - Self.iconSize.width) / 2).rounded(), y: ((tileSize - Self.iconSize.height) / 2).rounded())
        updateDockLabelIconPosition()
    }

    func highlightFrame() -> CGRect {
        let tileSize = Appearance.commandSwitcherTileSize
        let backgroundSize = Appearance.commandSwitcherBackgroundSize
        let originX = ((tileSize - backgroundSize) / 2).rounded()
        let originY = ((tileSize - backgroundSize) / 2).rounded()
        return CGRect(x: originX, y: originY, width: backgroundSize, height: backgroundSize)
    }

    func updateHighlight(isFocused: Bool, isHovered: Bool, showLabel: Bool) {
        label.isHidden = !showLabel
        if showLabel {
            updateLabelFrame()
        }
        highlightView?.removeFromSuperview()
        highlightView = nil
        let shouldShowHighlight = isFocused || isHovered
        guard shouldShowHighlight else { return }
        let newView = makeCommandSwitcherSelectionView()
        newView.frame = highlightFrame()
        newView.wantsLayer = true
        newView.layer?.zPosition = -1
        newView.updateAppearance(isFocused: isFocused)
        addSubview(newView, positioned: .below, relativeTo: nil)
        highlightView = newView
    }

    private func updateLabelFrame() {
        let tileSize = frame.width
        let labelHeight = label.cell!.cellSize.height
        let minimumWidth = tileSize
        let measuredTitleWidth = fullTitleWidth
        let labelFrameWidth = min(Self.labelMaxWidth, max(minimumWidth, ceil(measuredTitleWidth) + 24))
        var xPosition = ((tileSize - labelFrameWidth) / 2).rounded()
        if let documentView = superview {
            let absoluteLeft = frame.origin.x + xPosition
            let absoluteRight = absoluteLeft + labelFrameWidth
            if absoluteLeft < 0 {
                xPosition -= absoluteLeft
            } else if absoluteRight > documentView.frame.width {
                xPosition -= absoluteRight - documentView.frame.width
            }
        }
        let yPosition = tileSize + Self.labelTopSpacing
        label.frame = NSRect(x: xPosition, y: yPosition, width: labelFrameWidth, height: labelHeight)
        label.setWidth(labelFrameWidth)
        applySearchHighlight()
        label.toolTip = measuredTitleWidth > labelFrameWidth - 24 ? fullTitle : nil
    }

    private func applySearchHighlight() {
        let attributes = titleAttributes()
        let query = Search.normalizedQuery((SwitcherSession.current?.searchQuery ?? ""))
        if query.isEmpty {
            label.attributedStringValue = NSAttributedString(string: fullTitle, attributes: attributes)
            return
        }
        let mutable = NSMutableAttributedString(string: fullTitle, attributes: attributes)
        let loweredTitle = fullTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let loweredQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let nsTitle = loweredTitle as NSString
        var searchRange = NSRange(location: 0, length: nsTitle.length)
        while true {
            let range = nsTitle.range(of: loweredQuery, options: [], range: searchRange)
            if range.location == NSNotFound { break }
            mutable.addAttribute(TileTitleView.searchHighlightBackgroundKey, value: Appearance.highlightFocusedBackgroundColor.withAlphaComponent(0.45), range: range)
            let nextLocation = range.location + max(1, range.length)
            searchRange = NSRange(location: nextLocation, length: nsTitle.length - nextLocation)
        }
        label.attributedStringValue = mutable
    }

    private func titleAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.baseWritingDirection = .leftToRight
        paragraphStyle.lineBreakMode = label.lineBreakMode
        return [.font: Appearance.font, .foregroundColor: Appearance.fontColor, .paragraphStyle: paragraphStyle]
    }

    private func updateDockLabelIcon(_ dockLabel: String?) {
        let displayLabel = CommandSwitcherStyle.displayedDockLabel(dockLabel)
        dockLabelIcon.isHidden = displayLabel == nil || Preferences.hideAppBadges || Appearance.iconSize == 0
        if let displayLabel, !dockLabelIcon.isHidden {
            dockLabelIcon.setText(displayLabel)
            dockLabelIcon.setAccessibilityLabel(CommandSwitcherStyle.badgeAccessibilityText(dockLabel) ?? displayLabel)
        }
    }

    func refreshDockLabel(_ dockLabel: String?) {
        updateDockLabelIcon(dockLabel)
        updateDockLabelIconPosition()
    }

    private func updateDockLabelIconPosition() {
        let iconSize = max(appIcon.frame.width, appIcon.frame.height)
        let badgeOffset = iconSize * 0.32
        let badgeX = appIcon.frame.midX + badgeOffset - dockLabelIcon.frame.width / 2
        let badgeY = appIcon.frame.midY - badgeOffset - dockLabelIcon.frame.height / 2
        dockLabelIcon.frame.origin = CGPoint(x: badgeX.rounded(), y: max(0, badgeY.rounded()))
    }

    private func getAppOrAndWindowTitle(_ element: Window) -> String {
        let appName = element.application.localizedName
        let windowTitle = element.title
        if Preferences.showTitles == .appName {
            return appName ?? windowTitle ?? ""
        }
        if Preferences.showTitles == .windowTitle {
            return windowTitle ?? appName ?? ""
        }
        if Preferences.showTitles == .appNameAndWindowTitle {
            return [appName, windowTitle].compactMap { $0 }.joined(separator: " | ")
        }
        return windowTitle ?? appName ?? ""
    }

    override func mouseUp(with event: NSEvent) {
        App.focusSelectedWindow(window_)
    }
}

protocol SelectionEffectView: NSView {
    func updateAppearance(isFocused: Bool)
}

func makeCommandSwitcherSelectionView() -> SelectionEffectView {
    if #available(macOS 26.0, *) {
        return CommandSwitcherGlassSelectionView()
    }
    return CommandSwitcherVisualEffectSelectionView()
}

@available(macOS 26.0, *)
final class CommandSwitcherGlassSelectionView: NSGlassEffectView, SelectionEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        style = .regular
        cornerRadius = Appearance.cellCornerRadius
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func updateAppearance(isFocused: Bool) {
        let opacity: CGFloat = isFocused ? 0.4 : 0.35
        cornerRadius = Appearance.cellCornerRadius
        tintColor = NSColor.black.withAlphaComponent(opacity)
        // let color = isFocused ? NSColor.red : NSColor.blue
        // cornerRadius = Appearance.cellCornerRadius
        // tintColor = color.withAlphaComponent(0.4)
    }
}

final class CommandSwitcherVisualEffectSelectionView: NSVisualEffectView, SelectionEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if #available(macOS 10.14, *) {
            material = .hudWindow
        } else {
            material = .light
        }
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Appearance.cellCornerRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    func updateAppearance(isFocused: Bool) {
        layer?.cornerRadius = Appearance.cellCornerRadius
    }
}
