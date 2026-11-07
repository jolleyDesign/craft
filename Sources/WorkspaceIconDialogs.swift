import AppKit
import UniformTypeIdentifiers

/// Dialogs and pickers for choosing a workspace's sidebar icon. Every path
/// funnels through ``TabManager/setWorkspaceIcon(_:toWorkspaceIds:)`` so the
/// context menu, multi-select, and persistence all share one mutation path.
/// A quick-pick SF Symbol shown inline in the workspace icon context submenu.
struct WorkspaceIconPreset: Identifiable {
    let symbol: String
    let name: String
    var id: String { symbol }
}

@MainActor
enum WorkspaceIconPicker {
    /// Curated quick-pick SF Symbols shown inline in the context submenu, each
    /// with a localized display name (mirrors the color palette quick picks).
    static func presetSymbols() -> [WorkspaceIconPreset] {
        [
            WorkspaceIconPreset(symbol: "folder.fill", name: String(localized: "workspaceIcon.preset.folder", defaultValue: "Folder")),
            WorkspaceIconPreset(symbol: "chevron.left.forwardslash.chevron.right", name: String(localized: "workspaceIcon.preset.code", defaultValue: "Code")),
            WorkspaceIconPreset(symbol: "terminal.fill", name: String(localized: "workspaceIcon.preset.terminal", defaultValue: "Terminal")),
            WorkspaceIconPreset(symbol: "hammer.fill", name: String(localized: "workspaceIcon.preset.build", defaultValue: "Build")),
            WorkspaceIconPreset(symbol: "ant.fill", name: String(localized: "workspaceIcon.preset.bug", defaultValue: "Bug")),
            WorkspaceIconPreset(symbol: "globe", name: String(localized: "workspaceIcon.preset.web", defaultValue: "Web")),
            WorkspaceIconPreset(symbol: "star.fill", name: String(localized: "workspaceIcon.preset.star", defaultValue: "Star")),
            WorkspaceIconPreset(symbol: "flag.fill", name: String(localized: "workspaceIcon.preset.flag", defaultValue: "Flag")),
            WorkspaceIconPreset(symbol: "bolt.fill", name: String(localized: "workspaceIcon.preset.bolt", defaultValue: "Bolt")),
            WorkspaceIconPreset(symbol: "heart.fill", name: String(localized: "workspaceIcon.preset.heart", defaultValue: "Heart")),
        ]
    }

    /// Prompts for an arbitrary SF Symbol name and applies it after validating
    /// that the symbol is renderable on this system.
    static func promptCustomSymbol(
        tabManager: TabManager,
        targetIds: [UUID],
        seed: WorkspaceIcon?
    ) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "workspaceIcon.symbol.title",
            defaultValue: "Choose SF Symbol"
        )
        alert.informativeText = String(
            localized: "workspaceIcon.symbol.message",
            defaultValue: "Enter an SF Symbol name, for example hammer.fill."
        )

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        if case .symbol(let existing) = seed {
            input.stringValue = existing
        }
        input.placeholderString = "hammer.fill"
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: "workspaceIcon.apply", defaultValue: "Apply"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))

        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        DispatchQueue.main.async {
            alertWindow.makeFirstResponder(input)
            input.selectText(nil)
        }

        guard runCmuxModalAlert(alert) == .alertFirstButtonReturn else { return }
        let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard RenderableSystemSymbol.isRenderable(trimmed) else {
            presentInvalidSymbolAlert(trimmed)
            return
        }
        tabManager.setWorkspaceIcon(.symbol(trimmed), toWorkspaceIds: targetIds)
    }

    /// Prompts for an emoji, opening the native macOS Character/Emoji palette so
    /// the user can pick one visually, then applies the first emoji entered.
    static func promptEmoji(
        tabManager: TabManager,
        targetIds: [UUID],
        seed: WorkspaceIcon?
    ) {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "workspaceIcon.emoji.title",
            defaultValue: "Choose Emoji"
        )
        alert.informativeText = String(
            localized: "workspaceIcon.emoji.message",
            defaultValue: "Pick an emoji from the palette, or type one here."
        )

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        if case .emoji(let existing) = seed {
            input.stringValue = existing
        }
        input.placeholderString = "🙂"
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: "workspaceIcon.apply", defaultValue: "Apply"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))

        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        DispatchQueue.main.async {
            alertWindow.makeFirstResponder(input)
            input.selectText(nil)
            // Float the system emoji palette over the dialog; double-clicking an
            // emoji there inserts it into the focused text field.
            NSApp.orderFrontCharacterPalette(input)
        }

        guard runCmuxModalAlert(alert) == .alertFirstButtonReturn else { return }
        guard let emoji = firstGrapheme(in: input.stringValue) else { return }
        tabManager.setWorkspaceIcon(.emoji(emoji), toWorkspaceIds: targetIds)
    }

    /// Presents an open panel restricted to images, imports the chosen file into
    /// the icon store, and applies it.
    static func chooseImage(tabManager: TabManager, targetIds: [UUID]) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.title = String(
            localized: "workspaceIcon.image.panel.title",
            defaultValue: "Choose Workspace Icon"
        )
        panel.prompt = String(
            localized: "workspaceIcon.image.panel.prompt",
            defaultValue: "Choose"
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let filename = WorkspaceIconStore.importImage(from: url) else {
            presentImageImportErrorAlert()
            return
        }
        tabManager.setWorkspaceIcon(.image(filename), toWorkspaceIds: targetIds)
    }

    // MARK: - Helpers

    /// The first grapheme cluster (a complete emoji, including flags and ZWJ
    /// sequences) in the string, or `nil` when empty.
    private static func firstGrapheme(in string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first)
    }

    private static func presentInvalidSymbolAlert(_ name: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "workspaceIcon.invalidSymbol.title",
            defaultValue: "Unknown SF Symbol"
        )
        let format = String(
            localized: "workspaceIcon.invalidSymbol.message",
            defaultValue: "“%@” isn’t a known SF Symbol name. Browse names in Apple’s SF Symbols app."
        )
        alert.informativeText = String.localizedStringWithFormat(format, name)
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        _ = runCmuxModalAlert(alert)
    }

    private static func presentImageImportErrorAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "workspaceIcon.imageImportError.title",
            defaultValue: "Couldn’t Use Image"
        )
        alert.informativeText = String(
            localized: "workspaceIcon.imageImportError.message",
            defaultValue: "That image couldn’t be read. Try a different PNG or JPEG file."
        )
        alert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
        _ = runCmuxModalAlert(alert)
    }
}
