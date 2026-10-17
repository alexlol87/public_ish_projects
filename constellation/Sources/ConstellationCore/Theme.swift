import Foundation

/// Role -> colour (hex `#RRGGBB`). The app maps these to its own colour type.
public struct Palette: Equatable {
    public let isDark: Bool
    public let background, text, accent, heading, link, code, tag, folderNode, noteNode, stale: String
}

public enum ThemeChoice: String, CaseIterable {
    case light = "Light", dark = "Dark", dracula = "Dracula", oneDark = "One Dark", system = "System"

    /// `systemIsDark` only matters for `.system`.
    public func palette(systemIsDark: Bool) -> Palette {
        switch self {
        case .system: (systemIsDark ? ThemeChoice.dark : .light).palette(systemIsDark: systemIsDark)
        case .light:
            Palette(isDark: false, background: "#FFFFFF", text: "#24292F", accent: "#0969DA", heading: "#8250DF", link: "#0969DA",
                    code: "#CF222E", tag: "#1A7F37", folderNode: "#BF8700", noteNode: "#0969DA", stale: "#D1242F")
        case .dark:
            Palette(isDark: true, background: "#1E1E1E", text: "#D4D4D4", accent: "#4DA3FF", heading: "#C586C0", link: "#4DA3FF",
                    code: "#CE9178", tag: "#4EC9B0", folderNode: "#E5A50A", noteNode: "#4DA3FF", stale: "#F85149")
        case .dracula:
            Palette(isDark: true, background: "#282A36", text: "#F8F8F2", accent: "#BD93F9", heading: "#FF79C6", link: "#8BE9FD",
                    code: "#F1FA8C", tag: "#50FA7B", folderNode: "#FFB86C", noteNode: "#BD93F9", stale: "#FF5555")
        case .oneDark:
            Palette(isDark: true, background: "#282C34", text: "#ABB2BF", accent: "#61AFEF", heading: "#E06C75", link: "#61AFEF",
                    code: "#98C379", tag: "#56B6C2", folderNode: "#D19A66", noteNode: "#61AFEF", stale: "#BE5046")
        }
    }
}
