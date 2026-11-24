#if os(macOS)
import SwiftUI
import MaintenanceCore

struct StorageMap: View {
    let entries: [Entry]
    let hu: Bool
    let busy: Bool
    let open: (String) -> Void
    private let colors: [Color] = [.blue, .teal, .indigo, .purple, .mint, .cyan, .orange, .pink, .brown, .gray]
    var body: some View {
        let segments = StorageSegment.largest(entries)
        let remainder = max(0, 1 - segments.reduce(0) { $0 + $1.share })
        if !segments.isEmpty {
            GroupBox(hu ? "Interaktív tárhelytérkép" : "Interactive storage map") {
                VStack(alignment: .leading, spacing: 7) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                                Button { open(segment.entry.path) } label: {
                                    Rectangle().fill(colors[index % colors.count].opacity(segment.entry.complete ? 0.85 : 0.45))
                                        .overlay { if segment.share > 0.12 { Text(URL(fileURLWithPath: segment.entry.path).lastPathComponent).font(.caption.bold()).lineLimit(1).foregroundStyle(.white).padding(4) } }
                                }.buttonStyle(.plain).frame(width: proxy.size.width * segment.share).clipped().disabled(busy)
                                .help(segment.entry.path + " · " + ByteCountFormatter.string(fromByteCount: segment.entry.bytes, countStyle: .file))
                                .accessibilityLabel(segment.entry.path)
                            }
                            if remainder > 0 { Rectangle().fill(Color.gray.opacity(0.35)).frame(width: proxy.size.width * remainder).accessibilityLabel(hu ? "Egyéb vizsgált elemek" : "Other scanned items") }
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                    }.frame(height: 44)
                    Text(hu ? "Kattints egy szegmensre. A térkép csak a vizsgált logikai méreteket mutatja; a halvány szegmens részleges." : "Click a segment. Scanned logical sizes only; faded segments are partial.").font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
        }
    }
}
#endif
