import Foundation

/// file-manager-style selection over an ordered list of ids: click, ⌘-click, ⇧-click ranges, arrow keys,
/// select all, and box selection. Pure value type so the rules are testable.
public struct SelectionState: Equatable, Sendable {
    public private(set) var selected: Set<String> = []
    /// Where a shift-range starts.
    public private(set) var anchor: String?
    /// Where arrow keys continue from.
    public private(set) var cursor: String?

    public init() {}

    public var isEmpty: Bool { selected.isEmpty }
    public var count: Int { selected.count }
    public func contains(_ id: String) -> Bool { selected.contains(id) }

    /// The selection in display order (for drags, deletes and moves).
    public func ordered(by order: [String]) -> [String] { order.filter(selected.contains) }

    /// A click on `id`. Plain: select only it. ⌘: toggle it. ⇧: select from the anchor to it
    /// (⌘⇧ adds that range to what is already selected).
    public mutating func click(_ id: String, order: [String], command: Bool, shift: Bool) {
        if shift, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            let range = Set(order[min(from, to)...max(from, to)])
            selected = command ? selected.union(range) : range
        } else if command {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            anchor = id
        } else {
            selected = [id]
            anchor = id
        }
        cursor = id
    }

    public mutating func selectAll(_ order: [String]) {
        selected = Set(order)
        anchor = order.first
        cursor = order.last
    }

    public mutating func clear() {
        selected = []
        anchor = nil
        cursor = nil
    }

    /// Box selection: `hits` are the items the box touches. With `additive` (⌘ or ⇧ held when the
    /// drag began) they join `base`, the selection from before the drag; otherwise they replace it.
    public mutating func box(hits: Set<String>, base: Set<String>, additive: Bool, order: [String]) {
        selected = additive ? base.union(hits) : hits
        if let first = order.first(where: hits.contains) {
            anchor = first
            cursor = order.last(where: hits.contains)
        }
    }

    /// Arrow keys: move by `offset` items (±1 for left/right, ±columns for up/down). With `extend`
    /// (⇧) the selection grows from the anchor.
    public mutating func move(by offset: Int, order: [String], extend: Bool) {
        guard !order.isEmpty else { return }
        guard let base = cursor ?? anchor, let index = order.firstIndex(of: base), !selected.isEmpty else {
            let id = offset >= 0 ? order[0] : order[order.count - 1]
            selected = [id]
            anchor = id
            cursor = id
            return
        }
        let target = order[max(0, min(order.count - 1, index + offset))]
        if extend, let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: target) {
            selected = Set(order[min(from, to)...max(from, to)])
        } else {
            selected = [target]
            anchor = target
        }
        cursor = target
    }

    /// Replace the selection wholesale (used by the native list's own selection).
    public mutating func set(_ ids: Set<String>) {
        selected = ids
        if let anchor, !ids.contains(anchor) { self.anchor = nil }
        if let cursor, !ids.contains(cursor) { self.cursor = nil }
    }

    /// Drop ids that no longer exist (after a move, trash or refresh).
    public mutating func prune(keeping valid: Set<String>) {
        selected = selected.intersection(valid)
        if let anchor, !valid.contains(anchor) { self.anchor = nil }
        if let cursor, !valid.contains(cursor) { self.cursor = nil }
    }
}
