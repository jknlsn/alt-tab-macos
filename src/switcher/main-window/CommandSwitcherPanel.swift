import Cocoa

class CommandSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    static var shared: CommandSwitcherPanel!
    private var frozenTopCenter: NSPoint?
    private var highWaterHeight: CGFloat = 0

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        CommandSwitcherView.initialize()
        contentView = CommandSwitcherView.contentView
        collectionBehavior = .canJoinAllSpaces
        level = .popUpMenu
        setAccessibilitySubrole(.unknown)
        setAccessibilityLabel(App.name)
        updateAppearance()
        Self.shared = self
    }

    func updateAppearance() {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
    }

    func updateContents(_ preservedScrollOrigin: CGPoint?) {
        caTransaction {
            CommandSwitcherView.updateItemsAndLayout(preservedScrollOrigin)
            guard SwitcherSession.isActive else { return }
            setContentSize(CommandSwitcherView.contentView.frame.size)
            guard SwitcherSession.isActive else { return }
            repositionOrFreeze()
        }
        CommandSwitcherView.clearNeedsLayout()
    }

    private func repositionOrFreeze() {
        let size = frame.size
        guard TilesView.isSearchModeOn else {
            NSScreen.preferred.repositionPanel(self)
            resetFrozenPosition()
            return
        }
        if size.height > highWaterHeight {
            NSScreen.preferred.repositionPanel(self)
            highWaterHeight = size.height
            frozenTopCenter = NSPoint(x: frame.midX, y: frame.maxY)
        } else if let topCenter = frozenTopCenter {
            setFrameOrigin(NSPoint(x: topCenter.x - size.width * 0.5, y: topCenter.y - size.height))
        }
    }

    func resetFrozenPosition() {
        frozenTopCenter = nil
        highWaterHeight = 0
    }

    override func orderOut(_ sender: Any?) {
        CommandSwitcherView.clearNeedsLayout()
        if Preferences.fadeOutAnimation {
            NSAnimationContext.runAnimationGroup(
                { _ in animator().alphaValue = 0 },
                completionHandler: { super.orderOut(sender) }
            )
        } else {
            alphaValue = 0
            super.orderOut(sender)
        }
    }

    func show() {
        updateAppearance()
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        ContextMenuEvents.toggle(true)
        CursorEvents.toggle(true)
        DispatchQueue.main.async { CommandSwitcherView.scrollView.flashScrollers() }
    }
}

extension CommandSwitcherPanel: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async {
            if SwitcherSession.isActive {
                CommandSwitcherPanel.shared.makeKeyAndOrderFront(nil)
            }
            MainMenu.toggle(true)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        DispatchQueue.main.async {
            MainMenu.toggle(false)
            if TilesView.isSearchEditing {
                MainMenu.toggleEditMenu(true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Applications.manuallyRefreshAllWindows()
        }
    }
}
