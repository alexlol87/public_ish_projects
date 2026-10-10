import AppKit
import BorderCore
import SwiftUI

/// Edits the palette: order matters because ties in "least used color" go to the color higher in the list.
@MainActor
struct PaletteEditorView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A new window gets the color used least among visible windows; ties go to the color higher in "
                 + "the list. Drag rows or use the arrows to reorder.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                // Indices as IDs: the palette may hold the same color twice, so colors are not unique keys.
                ForEach(settings.palette.indices, id: \.self) { index in
                    row(at: index)
                }
                .onMove { source, destination in
                    settings.palette.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)

            HStack {
                Button {
                    settings.palette.append(nextNewColor())
                } label: {
                    Label("Add Color", systemImage: "plus")
                }
                Spacer()
                Button("Reset to Default Colors") {
                    settings.palette = Palette.defaultColors
                }
                .disabled(settings.palette == Palette.defaultColors)
            }
        }
        .padding(20)
    }

    private func row(at index: Int) -> some View {
        let color = index < settings.palette.count ? settings.palette[index] : Palette.defaultColors[0]
        let count = settings.palette.count
        return HStack(spacing: 10) {
            SwiftUI.ColorPicker("Color", selection: colorBinding(at: index), supportsOpacity: true)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(Palette.name(for: color))
                Text(color.hex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                settings.palette.swapAt(index, index - 1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .help("Move up")
            Button {
                settings.palette.swapAt(index, index + 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index >= count - 1)
            .help("Move down")
            Button {
                settings.palette.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(count <= 1)
            .help(count <= 1 ? "The palette needs at least one color" : "Remove this color")
        }
        .buttonStyle(.borderless)
    }

    /// Bridges a palette entry to SwiftUI's color picker. Bounds-checked because SwiftUI can still read a row's
    /// binding for a moment after that row was removed.
    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: {
                guard index < settings.palette.count else { return Color.clear }
                return settings.palette[index].settingsSwatchColor
            },
            set: { newValue in
                guard index < settings.palette.count, let rgba = RGBAColor.fromSettingsColor(newValue) else { return }
                settings.palette[index] = rgba
            }
        )
    }

    /// First default color the user removed, then a few extras, then evenly spread hues (golden-angle steps), so
    /// "Add" usually yields a color that is clearly different from the ones already listed.
    private func nextNewColor() -> RGBAColor {
        let extras = ["#5E5CE6", "#A3E635", "#E879F9", "#F43F5E", "#94A3B8", "#FFFFFF"]
            .compactMap { RGBAColor(hex: $0) }
        if let unused = (Palette.defaultColors + extras).first(where: { !settings.palette.contains($0) }) {
            return unused
        }
        let hue = (Double(settings.palette.count) * 0.618_033_988_749_895).truncatingRemainder(dividingBy: 1)
        return Self.color(hue: hue, saturation: 0.7, brightness: 0.9)
    }

    /// HSB -> sRGB, all components 0...1.
    private static func color(hue: Double, saturation: Double, brightness: Double) -> RGBAColor {
        let sector = hue * 6
        let index = Int(sector.rounded(.down)) % 6
        let fraction = sector - sector.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        let v = brightness
        switch index {
        case 0: return RGBAColor(red: v, green: t, blue: p)
        case 1: return RGBAColor(red: q, green: v, blue: p)
        case 2: return RGBAColor(red: p, green: v, blue: t)
        case 3: return RGBAColor(red: p, green: q, blue: v)
        case 4: return RGBAColor(red: t, green: p, blue: v)
        default: return RGBAColor(red: v, green: p, blue: q)
        }
    }
}
