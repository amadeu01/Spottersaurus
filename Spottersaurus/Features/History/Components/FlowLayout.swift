import SwiftUI

struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: Double = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + spacing * Double(max(rows.count - 1, 0))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX + xOffset(for: row.width, in: bounds.width)
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: Double) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width

            if proposedWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }

            current.append(Item(index: index, size: size), spacing: spacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private func xOffset(for rowWidth: Double, in containerWidth: Double) -> Double {
        switch alignment {
        case .center:
            max((containerWidth - rowWidth) / 2, 0)
        case .trailing:
            max(containerWidth - rowWidth, 0)
        default:
            0
        }
    }

    private struct Item {
        var index: Int
        var size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: Double = 0
        var height: Double = 0

        mutating func append(_ item: Item, spacing: Double) {
            width += items.isEmpty ? item.size.width : spacing + item.size.width
            height = max(height, item.size.height)
            items.append(item)
        }
    }
}

#Preview {
    FlowLayout(alignment: .leading, spacing: 8) {
        ForEach(["Grind rep 2", "Rack It rep 4", "Squat", "Bench Press", "Deadlift"], id: \.self) { label in
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.2), in: Capsule())
        }
    }
    .padding()
    .frame(width: 220)
}
