#if canImport(AppKit)
import ConstellationCore
import SwiftUI

enum SidebarTab: String, CaseIterable { case files = "Files", tags = "Tags" }

/// Tags tab: foldable tree (name or count order), then the Notes of the selected Tag with the line holding it.
struct TagsView: View {
    let index: TagIndex
    @Binding var selected: String?
    let open: (TagIndex.Hit) -> Void
    @State private var sort = TagIndex.Sort.name

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $sort) { Text("Name").tag(TagIndex.Sort.name); Text("Count").tag(TagIndex.Sort.count) }
                .pickerStyle(.segmented).padding(.horizontal, 8)
            List(index.tree(sortedBy: sort), children: \.optionalChildren, selection: $selected) { node in
                HStack { Text(node.name); Spacer(); Text("\(node.count)").foregroundStyle(.secondary) }.tag(node.tag)
            }
            if let selected {
                Divider()
                List(Array(index.notes(for: selected).enumerated()), id: \.offset) { _, hit in
                    Button { open(hit) } label: {
                        VStack(alignment: .leading) {
                            Text(hit.path).font(.caption).foregroundStyle(.secondary)
                            Text(hit.line).lineLimit(2)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

private extension TagIndex.Node {
    var optionalChildren: [TagIndex.Node]? { children.isEmpty ? nil : children }
}

extension TagIndex.Node: Identifiable { public var id: String { tag } }
#endif
