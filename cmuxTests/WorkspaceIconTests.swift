import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Behavior tests for workspace sidebar icons: the `WorkspaceIcon` value type,
/// its persistence bridge, and round-tripping through session snapshots
/// (including backward/forward compatibility with manifests that predate or
/// post-date the feature).
@MainActor
@Suite struct WorkspaceIconTests {

    // MARK: - Persistence bridge

    @Test func persistedBridgeRoundTripsEveryKind() {
        let cases: [WorkspaceIcon] = [
            .symbol("hammer.fill"),
            .emoji("🔨"),
            .image("abc.png"),
        ]
        for icon in cases {
            let restored = WorkspaceIcon(persisted: icon.persisted)
            #expect(restored == icon)
        }
    }

    @Test func persistedKindStringsAreStable() {
        // These strings live in persisted manifests; changing them silently
        // breaks restore of existing sessions.
        #expect(WorkspaceIcon.symbol("x").persisted.kind == "symbol")
        #expect(WorkspaceIcon.emoji("x").persisted.kind == "emoji")
        #expect(WorkspaceIcon.image("x").persisted.kind == "image")
    }

    @Test func unknownPersistedKindDecodesToNil() {
        let unknown = PersistedWorkspaceIcon(kind: "lottie", value: "anim.json")
        #expect(WorkspaceIcon(persisted: unknown) == nil)
    }

    @Test func emptyPersistedValueDecodesToNil() {
        #expect(WorkspaceIcon(persisted: PersistedWorkspaceIcon(kind: "symbol", value: "  ")) == nil)
        #expect(WorkspaceIcon(persisted: PersistedWorkspaceIcon(kind: "emoji", value: "")) == nil)
    }

    // MARK: - Sanitization

    @Test func sanitizedTrimsAndRejectsEmpty() {
        #expect(WorkspaceIcon.symbol("  star.fill  ").sanitized == .symbol("star.fill"))
        #expect(WorkspaceIcon.emoji("   ").sanitized == nil)
    }

    @Test func sanitizedStripsImagePathComponents() {
        // A crafted snapshot must never resolve outside the icon store.
        #expect(WorkspaceIcon.image("../../etc/passwd").sanitized == .image("passwd"))
        #expect(WorkspaceIcon.image("WorkspaceIcons/abc.png").sanitized == .image("abc.png"))
    }

    // MARK: - Snapshot round-trip

    @Test func snapshotRoundTripPreservesIcon() throws {
        for icon in [WorkspaceIcon.symbol("flag.fill"), .emoji("⭐️"), .image("xyz.png")] {
            let snapshot = makeSnapshot(icon: icon.persisted)
            let decoded = try JSONDecoder().decode(
                SessionWorkspaceSnapshot.self,
                from: JSONEncoder().encode(snapshot)
            )
            #expect(decoded.icon == icon.persisted)
            #expect(WorkspaceIcon(persisted: decoded.icon!) == icon)
        }
    }

    @Test func legacySnapshotWithoutIconDecodesToNil() throws {
        // A manifest written before icons existed simply omits the key. Encode a
        // real snapshot (so the layout etc. use the canonical format), strip the
        // icon key, and confirm it still decodes with no icon.
        let data = try JSONEncoder().encode(makeSnapshot(icon: nil))
        var object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "icon")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionWorkspaceSnapshot.self, from: stripped)
        #expect(decoded.icon == nil)
    }

    @Test func forwardCompatUnknownIconKindStillDecodesWorkspace() throws {
        // A manifest written by a newer build with an unknown icon kind must
        // still decode the rest of the workspace; the icon just resolves to nil.
        let snapshot = makeSnapshot(icon: PersistedWorkspaceIcon(kind: "hologram", value: "v"))
        let decoded = try JSONDecoder().decode(
            SessionWorkspaceSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        #expect(decoded.processTitle == "zsh")
        #expect(decoded.icon.flatMap(WorkspaceIcon.init(persisted:)) == nil)
    }

    // MARK: - Workspace mutation

    @Test func setIconSanitizesAndClears() {
        let workspace = Workspace(title: "Terminal")
        #expect(workspace.icon == nil)

        workspace.setIcon(.symbol("  terminal.fill  "))
        #expect(workspace.icon == .symbol("terminal.fill"))

        workspace.setIcon(.emoji("   "))
        #expect(workspace.icon == nil)

        workspace.setIcon(.emoji("🚀"))
        #expect(workspace.icon == .emoji("🚀"))

        workspace.setIcon(nil)
        #expect(workspace.icon == nil)
    }

    // MARK: - Helpers

    private func makeSnapshot(icon: PersistedWorkspaceIcon?) -> SessionWorkspaceSnapshot {
        SessionWorkspaceSnapshot(
            processTitle: "zsh",
            customTitle: nil,
            customDescription: nil,
            customColor: nil,
            icon: icon,
            isPinned: false,
            currentDirectory: "/tmp",
            focusedPanelId: nil,
            layout: .pane(SessionPaneLayoutSnapshot(panelIds: [], selectedPanelId: nil)),
            panels: [],
            statusEntries: [],
            logEntries: []
        )
    }
}
