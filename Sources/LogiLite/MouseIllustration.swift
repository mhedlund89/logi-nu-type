import AppKit
import SwiftUI

/// One numbered marker on an illustration, with its legend text. `anchor` is in the image's pixel coordinates.
struct SpecCallout: Identifiable {
    let index: Int
    let title: String
    let value: String
    let anchor: CGPoint?
    var id: Int { index }
}

/// A hand-drawn spec-sheet illustration with numbered markers on the real parts and an assignment legend.
/// Light mode multiplies the art onto the paper colour; dark mode inverts it and screens it on.
struct SpecIllustration<Fallback: View>: View {
    let image: NSImage?
    let imageSize: CGSize
    let callouts: [SpecCallout]
    let connected: Bool
    let p: WirePalette
    var selected: Int? = nil
    var legendColumns = 2
    var onSelect: ((Int) -> Void)? = nil
    @ViewBuilder var fallback: () -> Fallback

    @Environment(\.colorScheme) private var scheme

    /// Load a PNG from the app bundle, or from Support/Resources when running from .build (render aid).
    static func resource(_ name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) {
            return img
        }
        let rel = "Support/Resources/\(name).png"
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            if let img = NSImage(contentsOf: dir.appendingPathComponent(rel)) { return img }
            dir.deleteLastPathComponent()
        }
        return NSImage(contentsOf: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(rel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image { artwork(image) } else { fallback() }
            legend
        }
    }

    private func artwork(_ art: NSImage) -> some View {
        GeometryReader { g in
            let s = g.size.width / imageSize.width
            ZStack(alignment: .topLeading) {
                Group {
                    if scheme == .dark {
                        Image(nsImage: art).resizable().interpolation(.high).colorInvert().blendMode(.screen)
                    } else {
                        Image(nsImage: art).resizable().interpolation(.high).blendMode(.multiply)
                    }
                }
                .opacity(connected ? 1 : 0.55)
                .accessibilityHidden(true)

                ForEach(callouts) { c in
                    if let a = c.anchor {
                        marker(c, size: g.size.width < 450 ? 15 : 20).position(x: a.x * s, y: a.y * s)
                    }
                }
            }
        }
        .aspectRatio(imageSize, contentMode: .fit)
        .overlay(alignment: .bottomTrailing) {
            if !connected {
                Text("— UNIT NOT CONNECTED —").font(WireFont.label(8, .bold)).foregroundStyle(p.faint).padding(4)
            }
        }
    }

    private func marker(_ c: SpecCallout, size: CGFloat) -> some View {
        let on = c.index == selected
        let body = ZStack {
            Circle().fill(on ? p.ink : p.paper)
            Circle().strokeBorder(p.ink, lineWidth: 1.4)
            Text("\(c.index)").font(WireFont.fixed(size * 0.5, .bold)).foregroundStyle(on ? p.paper : p.ink)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(p.ink, lineWidth: 1).padding(-4).opacity(on ? 1 : 0))
        .shadow(color: p.paper, radius: 2)
        return Group {
            if let onSelect {
                Button { onSelect(c.index) } label: { body.contentShape(Circle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(c.index). \(c.title): \(c.value)")
            } else {
                body.accessibilityHidden(true)
            }
        }
    }

    private var legend: some View {
        let ordered = callouts.sorted { $0.index < $1.index }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .leading), count: legendColumns)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(ordered) { c in legendRow(c) }
        }
    }

    @ViewBuilder private func legendRow(_ c: SpecCallout) -> some View {
        let on = c.index == selected
        let row = HStack(spacing: 7) {
            Text("\(c.index)").font(WireFont.label(9, .bold))
                .foregroundStyle(on ? p.paper : p.ink)
                .frame(width: 15, height: 15)
                .background(on ? p.ink : .clear)
                .overlay(Rectangle().strokeBorder(p.ink, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(WireFont.label(7)).foregroundStyle(p.faint)
                Text(c.value).font(WireFont.label(9, .semibold)).foregroundStyle(p.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        if let onSelect {
            Button { onSelect(c.index) } label: { row }.buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            row
        }
    }
}

/// The cutaway illustration of the MX Master 2S (falls back to the vector schematic if the PNG is missing).
struct MouseIllustration: View {
    let callouts: [MouseSchematic.Callout]
    let connected: Bool
    let p: WirePalette
    var selected: Int? = nil
    var legendColumns = 2
    var onSelect: ((MouseSchematic.Part) -> Void)? = nil

    /// Pixel size of mouse-cutaway.png; anchors are in these coordinates.
    static let imageSize = CGSize(width: 872, height: 536)
    static let anchors: [MouseSchematic.Part: CGPoint] = [
        .wheel: CGPoint(x: 240, y: 274), .wheelMode: CGPoint(x: 343, y: 151), .thumbWheel: CGPoint(x: 540, y: 209),
        .forward: CGPoint(x: 580, y: 237), .back: CGPoint(x: 540, y: 292), .gesture: CGPoint(x: 650, y: 276),
    ]
    static let image = SpecIllustration<EmptyView>.resource("mouse-cutaway")

    var body: some View {
        SpecIllustration(image: Self.image, imageSize: Self.imageSize,
                         callouts: callouts.map { SpecCallout(index: $0.index, title: $0.title, value: $0.value, anchor: Self.anchors[$0.part]) },
                         connected: connected, p: p, selected: selected, legendColumns: legendColumns,
                         onSelect: onSelect.map { cb in { i in if let c = callouts.first(where: { $0.index == i }) { cb(c.part) } } }) {
            MouseSchematic(callouts: callouts, connected: connected, p: p, selected: selected, layout: .side)
                .aspectRatio(MouseSchematic.designSize(.side), contentMode: .fit)
        }
    }
}

/// The top view of the MX Keys, from the keyboard illustration sheet.
struct KeyboardIllustration: View {
    let callouts: [SpecCallout]
    let connected: Bool
    let p: WirePalette
    var selected: Int? = nil
    var legendColumns = 2
    var onSelect: ((Int) -> Void)? = nil

    /// Pixel size of keyboard-top.png; anchors are in these coordinates.
    static let imageSize = CGSize(width: 654, height: 212)
    static let image = SpecIllustration<EmptyView>.resource("keyboard-top")

    var body: some View {
        SpecIllustration(image: Self.image, imageSize: Self.imageSize, callouts: callouts, connected: connected, p: p,
                         selected: selected, legendColumns: legendColumns, onSelect: onSelect) {
            Text("— KEYBOARD DRAWING MISSING —").font(WireFont.label(9, .bold)).foregroundStyle(p.faint)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }
}
