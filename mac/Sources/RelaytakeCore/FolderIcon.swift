import Foundation

/// A folder's emoji lives in its real name ("🔥 Hot Takes"), so it shows in the file manager too and there is no
/// extra file to keep in sync. These rules split a name into its icon and title and put them back together.
public enum FolderName {
    /// The folder every library starts with.
    public static let defaultName = "🔥 Hot Takes"
    public static let defaultTitle = "Hot Takes"

    /// Emoji offered in the icon picker.
    public static let suggestions: [String] = [
        "🔥", "⭐️", "💡", "🎯", "🚀", "📌", "📁", "🗂️", "📺", "🎬", "🎥", "🎙️",
        "💬", "📣", "📝", "📊", "📈", "🧪", "🛠️", "🐞", "✅", "⏳", "💼", "🏠",
        "🎓", "🧠", "❤️", "🎉", "☕️", "🌎", "🔒", "🗓️", "🤝", "🏆", "🎨", "🌱",
    ]

    /// The emoji at the very start of `text`, if it starts with one.
    public static func leadingEmoji(in text: String) -> String? {
        guard let first = text.first, isEmoji(first) else { return nil }
        return String(first)
    }

    /// Splits "🔥 Hot Takes" into the icon and "Hot Takes". A name without a leading emoji, or one that is
    /// only an emoji, has no icon.
    public static func split(_ name: String) -> (icon: String?, title: String) {
        guard let icon = leadingEmoji(in: name) else { return (nil, name) }
        let rest = String(name.dropFirst()).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? (nil, name) : (icon, rest)
    }

    public static func compose(icon: String?, title: String) -> String {
        guard let icon = icon.flatMap(leadingEmoji(in:)) else { return title }
        return title.isEmpty ? icon : icon + " " + title
    }

    /// What a folder is called after the user types `text` in the rename box. Typing a name keeps the
    /// icon; starting with an emoji sets it; typing only an emoji changes just the icon.
    public static func renamed(_ current: String, to text: String) -> String {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let old = split(current)
        if let icon = leadingEmoji(in: typed) {
            let rest = String(typed.dropFirst()).trimmingCharacters(in: .whitespaces)
            return compose(icon: icon, title: rest.isEmpty ? old.title : rest)
        }
        return compose(icon: old.icon, title: typed)
    }

    // Digits, # and * are "emoji" to Unicode but not what anyone means by an icon.
    private static func isEmoji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value >= 0x231A)
    }
}

public extension FolderNode {
    var icon: String? { FolderName.split(name).icon }
    /// The name without its emoji.
    var title: String { FolderName.split(name).title }
}

public extension TakeLibrary {
    /// Gives a folder an emoji icon (or removes it with nil). Returns the folder's new relative path.
    @discardableResult
    static func setFolderIcon(_ path: String, to icon: String?, root: URL, fileManager: FileManager = .default) throws -> String {
        let current = (path as NSString).lastPathComponent
        let name = FolderName.compose(icon: icon, title: FolderName.split(current).title)
        return try renameFolder(path, to: name, root: root, fileManager: fileManager)
    }

    /// Makes sure the library has a Hot Takes folder. Returns whether it created one. A folder already
    /// called Hot Takes, with or without an icon, counts.
    @discardableResult
    static func ensureDefaultFolder(root: URL, fileManager: FileManager = .default) throws -> Bool {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let exists = folders(in: root, fileManager: fileManager).contains {
            $0.title.localizedCaseInsensitiveCompare(FolderName.defaultTitle) == .orderedSame
        }
        guard !exists else { return false }
        try fileManager.createDirectory(at: root.appendingPathComponent(FolderName.defaultName), withIntermediateDirectories: false)
        return true
    }
}
