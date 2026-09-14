//
//  TreemapLayout.swift
//  BinaryExplorer
//
//  Squarified treemap (Bruls, Huizing & van Wijk). Produces tiles whose aspect
//  ratios stay close to 1, which is what makes the 3D city readable.
//

import CoreGraphics

struct TreemapTile<Item> {
    var item: Item
    var rect: CGRect
    var weight: Double
}

enum TreemapLayout {

    /// Lays `items` out inside `rect`, largest first.
    static func layout<Item>(_ items: [Item],
                             in rect: CGRect,
                             weight: (Item) -> Double) -> [TreemapTile<Item>] {
        let weighted = items
            .map { (item: $0, weight: max(weight($0), 0)) }
            .filter { $0.weight > 0 }
            .sorted { $0.weight > $1.weight }
        guard !weighted.isEmpty, rect.width > 0, rect.height > 0 else { return [] }

        let total = weighted.reduce(0) { $0 + $1.weight }
        let scale = Double(rect.width * rect.height) / total

        var result: [TreemapTile<Item>] = []
        var remaining = weighted.map { (item: $0.item, area: $0.weight * scale, weight: $0.weight) }
        var free = rect
        var row: [(item: Item, area: Double, weight: Double)] = []

        func shortestSide(_ r: CGRect) -> Double { Double(min(r.width, r.height)) }

        /// Worst aspect ratio produced by adding `candidate` to the current row.
        func worstRatio(_ row: [(item: Item, area: Double, weight: Double)], side: Double) -> Double {
            guard !row.isEmpty, side > 0 else { return .greatestFiniteMagnitude }
            let sum = row.reduce(0) { $0 + $1.area }
            guard sum > 0 else { return .greatestFiniteMagnitude }
            let maxArea = row.map(\.area).max() ?? 0
            let minArea = row.map(\.area).min() ?? 0
            let side2 = side * side
            let sum2 = sum * sum
            return max(side2 * maxArea / sum2, sum2 / (side2 * minArea))
        }

        func placeRow(_ row: [(item: Item, area: Double, weight: Double)], in free: CGRect) -> CGRect {
            let sum = row.reduce(0) { $0 + $1.area }
            guard sum > 0 else { return free }
            let horizontal = free.width >= free.height

            if horizontal {
                let rowWidth = CGFloat(sum / Double(free.height))
                var y = free.minY
                for entry in row {
                    let height = CGFloat(entry.area / Double(rowWidth))
                    result.append(TreemapTile(item: entry.item,
                                              rect: CGRect(x: free.minX, y: y,
                                                           width: rowWidth, height: height),
                                              weight: entry.weight))
                    y += height
                }
                return CGRect(x: free.minX + rowWidth, y: free.minY,
                              width: max(0, free.width - rowWidth), height: free.height)
            } else {
                let rowHeight = CGFloat(sum / Double(free.width))
                var x = free.minX
                for entry in row {
                    let width = CGFloat(entry.area / Double(rowHeight))
                    result.append(TreemapTile(item: entry.item,
                                              rect: CGRect(x: x, y: free.minY,
                                                           width: width, height: rowHeight),
                                              weight: entry.weight))
                    x += width
                }
                return CGRect(x: free.minX, y: free.minY + rowHeight,
                              width: free.width, height: max(0, free.height - rowHeight))
            }
        }

        while !remaining.isEmpty {
            let candidate = remaining[0]
            let side = shortestSide(free)
            let currentWorst = worstRatio(row, side: side)
            let nextWorst = worstRatio(row + [candidate], side: side)

            if row.isEmpty || nextWorst <= currentWorst {
                row.append(candidate)
                remaining.removeFirst()
            } else {
                free = placeRow(row, in: free)
                row.removeAll()
                if free.width <= 0 || free.height <= 0 { break }
            }
        }
        if !row.isEmpty { _ = placeRow(row, in: free) }

        return result
    }
}
