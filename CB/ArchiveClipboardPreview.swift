import SwiftUI

struct ArchiveClipboardPreview: View {
    let data: Data
    let utiIdentifier: String?

    private var entries: [ZIPArchiveEntry] {
        ZIPArchiveParser.entries(in: data)
    }

    var body: some View {
        if entries.isEmpty {
            ContentUnavailableView(
                "Archive Preview Unavailable",
                systemImage: "archivebox",
                description: Text(utiIdentifier ?? "The archive format could not be inspected.")
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("\(entries.count) items", systemImage: "archivebox")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                        .foregroundStyle(.secondary)
                }

                Table(entries) {
                    TableColumn("Name") { entry in
                        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                    }
                    TableColumn("Size") { entry in
                        Text(
                            entry.isDirectory
                                ? "—"
                                : ByteCountFormatter.string(
                                    fromByteCount: Int64(entry.uncompressedSize),
                                    countStyle: .file
                                )
                        )
                    }
                    .width(min: 90, ideal: 110, max: 150)
                }
            }
        }
    }
}

struct ZIPArchiveEntry: Identifiable, Equatable {
    let name: String
    let uncompressedSize: UInt32

    var id: String {
        name
    }

    var isDirectory: Bool {
        name.hasSuffix("/")
    }
}

enum ZIPArchiveParser {
    static func entries(in data: Data) -> [ZIPArchiveEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else {
            return []
        }

        var entries: [ZIPArchiveEntry] = []
        var offset = 0
        while offset + 46 <= bytes.count {
            guard readUInt32(bytes, at: offset) == 0x02014B50 else {
                offset += 1
                continue
            }

            let uncompressedSize = readUInt32(bytes, at: offset + 24)
            let nameLength = Int(readUInt16(bytes, at: offset + 28))
            let extraLength = Int(readUInt16(bytes, at: offset + 30))
            let commentLength = Int(readUInt16(bytes, at: offset + 32))
            let nameStart = offset + 46
            let nameEnd = nameStart + nameLength
            guard nameEnd <= bytes.count else {
                break
            }

            let nameData = Data(bytes[nameStart..<nameEnd])
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "Unknown item"
            entries.append(ZIPArchiveEntry(name: name, uncompressedSize: uncompressedSize))
            offset = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else {
            return 0
        }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else {
            return 0
        }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
