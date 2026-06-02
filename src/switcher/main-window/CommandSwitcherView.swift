import Cocoa

enum CommandSwitcherView {
    static var scrollView: ScrollView!
    static var contentView: EffectView!
    static var recycledViews = [CommandSwitcherItemView]()
    static var rows = [[CommandSwitcherItemView]]()
    private static var initialized = false
    private static var interactionToken: UInt64 = 0
    private static var lastHoverChangeToken: UInt64 = 0
    private static var lastSelectionChangeToken: UInt64 = 0
    static var shouldPreferHoveredLabel: Bool {
        SwitcherSession.current?.hoveredIndex != nil && lastHoverChangeToken > lastSelectionChangeToken
    }

    static func recordHoverChange() {
        interactionToken += 1
        lastHoverChangeToken = interactionToken
    }

    static func recordSelectionChange() {
        interactionToken += 1
        lastSelectionChangeToken = interactionToken
    }

    static func initialize() {
        TilesView.initialize()
        guard !initialized else { return }
        updateBackgroundView()
        while recycledViews.count < 20 { recycledViews.append(CommandSwitcherItemView()) }
        initialized = true
    }

    static func reset() {
        guard initialized else { return }
        updateBackgroundView()
        CommandSwitcherPanel.shared?.contentView = contentView
        recycledViews = recycledViews.indices.map { _ in CommandSwitcherItemView() }
        while recycledViews.count < 20 { recycledViews.append(CommandSwitcherItemView()) }
    }

    static func updateBackgroundView() {
        contentView = makeAppropriateEffectView()
        scrollView = ScrollView()
        TilesView.searchField.isHidden = TilesView.searchMode == .off
        contentView.addSubview(TilesView.searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(TilesView.noWindowLabel)
    }

    static func ensureRecycledViews() {
        while recycledViews.count < Windows.list.count { recycledViews.append(CommandSwitcherItemView()) }
    }

    static func updateItemsAndLayout(_ preservedScrollOrigin: CGPoint?) {
        ensureRecycledViews()
        let widthMax = TilesPanel.maxThumbnailsWidth().rounded()
        guard let (maxX, maxY) = layoutItems(widthMax) else { return }
        layoutParentViews(maxX, maxY)
        highlightStartView()
        if let preservedScrollOrigin { restoreScrollOrigin(preservedScrollOrigin) }
    }

    static func currentScrollOrigin() -> CGPoint { scrollView.contentView.bounds.origin }

    static func clearNeedsLayout() {
        let views: [NSView] = [contentView as NSView, TilesView.searchField, TilesView.noWindowLabel, scrollView, scrollView.contentView, scrollView.documentView].compactMap { $0 }
        for view in views {
            view.needsLayout = false
            view.needsDisplay = false
            view.needsUpdateConstraints = false
        }
    }

    static func highlight(_ index: Int) {
        guard index >= 0 && index < recycledViews.count else { return }
        let focusedIndex = SwitcherSession.current?.selectedIndex
        let hoveredIndex = SwitcherSession.current?.hoveredIndex
        let preferHoveredLabel = shouldPreferHoveredLabel
        let labelIndex = preferHoveredLabel ? (hoveredIndex ?? focusedIndex) : focusedIndex
        for view in rows.joined() {
            let visibleIndex = view.indexInRecycledViews
            guard view.frame != .zero else { continue }
            let isFocused = visibleIndex == focusedIndex
            let isHovered = visibleIndex == hoveredIndex && visibleIndex != focusedIndex
            let showLabel = visibleIndex == labelIndex
            view.updateHighlight(isFocused: isFocused, isHovered: isHovered, showLabel: showLabel)
        }
    }

    static func focusSelectedItemIfPossible() {
        guard let idx = SwitcherSession.current?.selectedIndex, idx >= 0, idx < recycledViews.count else { return }
        App.activePanel.makeFirstResponder(recycledViews[idx])
    }

    static func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        guard let selectedIdx = SwitcherSession.current?.selectedIndex, selectedIdx < recycledViews.count else { return }
        let focusedViewFrame = recycledViews[selectedIdx].frame
        let originCenter = NSMidX(focusedViewFrame)
        guard let targetRow = nextRow(direction, allowWrap: allowWrap), !targetRow.isEmpty else { return }
        let leftSide = originCenter < NSMidX(contentView.frame)
        let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
        let iterable = leadingSide ? targetRow : targetRow.reversed()
        guard let targetView = iterable.first(where: {
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
            }
            return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
        }) ?? iterable.last else { return }
        Windows.updateSelectedAndHoveredWindowIndex(targetView.indexInRecycledViews)
    }

    static func updateHover() {
        guard !scrollView.isCurrentlyScrolling, !TilesView.hasMarkedText(), !ContextMenuEvents.isMenuOpen,
              let documentView = scrollView.documentView else { return }
        let location = documentView.convert(App.activePanel.mouseLocationOutsideOfEventStream, from: nil)
        if let target = findTarget(location) {
            Windows.updateSelectedAndHoveredWindowIndex(target.indexInRecycledViews, true)
        } else {
            resetHoveredWindow()
        }
    }

    static func resetHoveredWindow() {
        if let oldIndex = SwitcherSession.current?.hoveredIndex {
            SwitcherSession.current?.hoveredIndex = nil
            highlight(oldIndex)
            highlight(SwitcherSession.current?.selectedIndex ?? 0)
        }
    }

    static func view(_ index: Int) -> CommandSwitcherItemView? {
        guard index >= 0 && index < recycledViews.count else { return nil }
        return recycledViews[index]
    }

    private static func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [CommandSwitcherItemView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.selectedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap { nextRow = nextRow % rows.count } else { return nil }
            } else if nextRow < 0 {
                if allowWrap { nextRow = rows.count + nextRow } else { return nil }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) && (ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    private static func rowCounts(_ widthMax: CGFloat) -> [Int] {
        let visibleCount = Windows.list.filter { Windows.shouldDisplay($0) }.count
        guard visibleCount > 0 else { return [] }
        let tileSize = Appearance.commandSwitcherTileSize
        let edgePadding = Appearance.commandSwitcherEdgePadding
        let widthPerItem = tileSize + Appearance.interCellPadding
        let availableWidth = widthMax - edgePadding * 2
        let maxColumns = max(1, Int((availableWidth + Appearance.interCellPadding) / widthPerItem))
        let rowCount = Int(ceil(Double(visibleCount) / Double(maxColumns)))
        let minimumItemsPerRow = visibleCount / rowCount
        let rowsWithExtraItem = visibleCount % rowCount
        return (0..<rowCount).map { minimumItemsPerRow + ($0 < rowsWithExtraItem ? 1 : 0) }
    }

    private static func layoutItems(_ widthMax: CGFloat) -> (CGFloat, CGFloat)? {
        let tileSize = Appearance.commandSwitcherTileSize
        let edgePadding = Appearance.commandSwitcherEdgePadding
        let height = tileSize + CommandSwitcherItemView.labelTopSpacing + CommandSwitcherItemView.labelAreaHeight
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let startingX = isLeftToRight ? edgePadding : widthMax - edgePadding
        let visibleIndexes = Windows.list.indices.filter { Windows.shouldDisplay(Windows.list[$0]) }
        var newViews = [CommandSwitcherItemView]()
        var maxX = CGFloat.zero
        var currentY = Appearance.interCellPadding
        rows.removeAll(keepingCapacity: true)
        for (index, view) in recycledViews.enumerated() {
            if index >= Windows.list.count || !visibleIndexes.contains(index) {
                view.frame = .zero
                view.window_ = nil
            }
        }
        var visibleOffset = 0
        for (rowIndex, rowCount) in rowCounts(widthMax).enumerated() {
            rows.append([CommandSwitcherItemView]())
            var currentX = startingX
            for _ in 0..<rowCount {
                guard SwitcherSession.isActive else { return nil }
                let visibleIndex = visibleIndexes[visibleOffset]
                let view = recycledViews[visibleIndex]
                let window = Windows.list[visibleIndex]
                view.updateRecycledCellWithNewContent(window, visibleIndex, height)
                let width = view.frame.size.width
                view.frame.origin = CGPoint(x: App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width, y: currentY)
                currentX = (App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX + width + Appearance.interCellPadding : currentX - width - Appearance.interCellPadding).rounded(.down)
                maxX = max(isLeftToRight ? currentX + edgePadding : widthMax - currentX + edgePadding, maxX)
                rows[rowIndex].append(view)
                newViews.append(view)
                window.rowIndex = rowIndex
                visibleOffset += 1
            }
            currentY = (currentY + height + Appearance.interCellPadding).rounded(.down)
        }
        let maxY = rows.isEmpty ? Appearance.interCellPadding + height + Appearance.interCellPadding : currentY
        centerRows(maxX)
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY)
    }

    private static func centerRows(_ totalWidth: CGFloat) {
        guard totalWidth > 0 else { return }
        for row in rows {
            guard let minX = row.map({ $0.frame.minX }).min(), let maxX = row.map({ $0.frame.maxX }).max() else { continue }
            let rowWidth = maxX - minX
            let targetMinX = ((totalWidth - rowWidth) / 2).rounded()
            let delta = targetMinX - minX
            guard delta != 0 else { continue }
            row.forEach { $0.frame.origin.x += delta }
        }
    }

    private static func layoutParentViews(_ maxX: CGFloat, _ maxY: CGFloat) {
        let searchBarHeight = TilesView.searchField.fittingSize.height > 0 ? ceil(TilesView.searchField.fittingSize.height) : 30
        let searchBottomPadding = CGFloat(10)
        let searchReservedHeight = TilesView.searchMode == .off ? 0 : searchBarHeight + searchBottomPadding
        let heightMax = max(0, TilesPanel.maxThumbnailsHeight() - searchReservedHeight)
        let minWidth = min(TilesPanel.maxThumbnailsWidth(), 320)
        let thumbnailsWidth = max(min(maxX, TilesPanel.maxThumbnailsWidth()), TilesView.searchMode == .off ? (maxX == 0 ? minWidth : 0) : minWidth)
        let thumbnailsHeight = min(maxY, heightMax)
        let frameWidth = thumbnailsWidth + Appearance.windowPadding * 2
        let frameHeight = thumbnailsHeight + Appearance.windowPadding * 2 + searchReservedHeight
        let originY = Appearance.windowPadding
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        scrollView.frame.size = NSSize(width: thumbnailsWidth, height: max(0, thumbnailsHeight))
        scrollView.frame.origin = CGPoint(x: Appearance.windowPadding, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        TilesView.searchField.isHidden = TilesView.searchMode == .off
        if TilesView.searchMode != .off {
            let searchWidth = min(minWidth, 320)
            TilesView.searchField.frame.size = NSSize(width: searchWidth, height: searchBarHeight)
            let searchX = Appearance.windowPadding + (thumbnailsWidth - searchWidth) * 0.5
            TilesView.searchField.frame.origin = CGPoint(x: searchX, y: frameHeight - Appearance.windowPadding - searchBarHeight)
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        let isEmpty = maxX == 0
        TilesView.noWindowLabel.isHidden = !isEmpty
        if isEmpty {
            TilesView.noWindowLabel.sizeToFit()
            let labelX = Appearance.windowPadding + (thumbnailsWidth - TilesView.noWindowLabel.frame.width) * 0.5
            let labelY = scrollView.frame.origin.y + (scrollView.frame.height - TilesView.noWindowLabel.frame.height) * 0.5
            TilesView.noWindowLabel.frame.origin = CGPoint(x: labelX, y: labelY)
        }
    }

    private static func restoreScrollOrigin(_ scrollOrigin: CGPoint) {
        guard let documentView = scrollView.documentView else { return }
        let visibleSize = scrollView.contentView.bounds.size
        let documentSize = documentView.frame.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let clampedOrigin = CGPoint(x: min(max(0, scrollOrigin.x), maxX), y: min(max(0, scrollOrigin.y), maxY))
        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func highlightStartView() {
        if Windows.selectedWindow() != nil {
            highlight(SwitcherSession.current?.selectedIndex ?? 0)
        }
        if let hoveredIndex = SwitcherSession.current?.hoveredIndex,
           hoveredIndex >= 0,
           hoveredIndex < Windows.list.count,
           Windows.shouldDisplay(Windows.list[hoveredIndex]) {
            highlight(hoveredIndex)
        }
    }

    static func findTarget(_ location: NSPoint) -> CommandSwitcherItemView? {
        guard let documentView = scrollView.documentView else { return nil }
        for case let view as CommandSwitcherItemView in documentView.subviews {
            let expandedFrame = view.frame.insetBy(dx: 0, dy: -1)
            if expandedFrame.contains(location) { return view }
        }
        return nil
    }
}
