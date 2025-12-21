import AppKit

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return false
    }
    
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            NSApp.activate(ignoringOtherApps: true)
        }
        super.sendEvent(event)
    }

    // Allow dragging the borderless panel by clicking anywhere in the panel.
    override func mouseDown(with event: NSEvent) {
        self.performDrag(with: event)
    }
}
