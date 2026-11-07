import CmuxFoundation
import SwiftUI

/// Renders a workspace's sidebar icon for any of its three kinds.
///
/// SF Symbols render template-style and pick up `tint` (typically the workspace
/// color). Emoji and custom images render unmodified. All three kinds are laid
/// out into the same square so rows stay aligned regardless of icon kind.
struct WorkspaceIconView: View {
    @Environment(\.cmuxGlobalFontMagnificationPercent) private var globalFontMagnificationPercent

    let icon: WorkspaceIcon
    /// Target point size for the icon's bounding square (before global
    /// magnification). SF Symbols apply magnification internally; emoji and
    /// images are scaled here to match.
    let pointSize: CGFloat
    /// Tint applied to SF Symbol icons only.
    var tint: Color = .secondary

    private var magnifiedPointSize: CGFloat {
        GlobalFontMagnification.scaledSize(pointSize, percent: globalFontMagnificationPercent)
    }

    var body: some View {
        switch icon {
        case .symbol(let name):
            CmuxSystemSymbolImage(magnified: name, pointSize: pointSize, weight: .medium)
                .foregroundColor(tint)
        case .emoji(let emoji):
            Text(emoji)
                .font(.system(size: magnifiedPointSize * 0.92))
                .frame(width: magnifiedPointSize, height: magnifiedPointSize)
                .minimumScaleFactor(0.5)
        case .image(let filename):
            if let nsImage = WorkspaceIconStore.loadImage(filename: filename) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: magnifiedPointSize, height: magnifiedPointSize)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: max(2, magnifiedPointSize * 0.2),
                            style: .continuous
                        )
                    )
            } else {
                // The stored file is missing (e.g. moved between machines).
                // Reserve no visible space rather than show a broken glyph.
                Color.clear
                    .frame(width: magnifiedPointSize, height: magnifiedPointSize)
                    .accessibilityHidden(true)
            }
        }
    }
}
