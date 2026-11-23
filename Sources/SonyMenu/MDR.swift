import Foundation

/// Sony "MDR" framing used by WH-1000XM5 over Bluetooth RFCOMM.
///
///     '>' ESCAPED( type, seq, len:Int32BE, payload..., checksum ) '<'
///
/// Bytes 0x3C/0x3D/0x3E inside a frame are escaped as 0x3D, (byte - 0x10).
/// Protocol details follow mos9527/SonyHeadphonesClient (libmdr).
enum MDR {
    static let serviceUUID = "956C7B26-D49A-4BA8-B03F-B17D393CB6E2"

    enum DataType: UInt8 {
        case data = 0x00
        case ack = 0x01
        case dataMDR = 0x0C
        case dataMDRNo2 = 0x0E
    }

    struct Frame {
        let type: UInt8
        let seq: UInt8
        let payload: [UInt8]
    }

    private static let start: UInt8 = 0x3E
    private static let end: UInt8 = 0x3C
    private static let escape: UInt8 = 0x3D

    static func pack(type: DataType, seq: UInt8, payload: [UInt8]) -> [UInt8] {
        let n = UInt32(payload.count)
        var raw: [UInt8] = [type.rawValue, seq,
                            UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
                            UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)]
        raw += payload
        raw.append(raw.reduce(0, &+))

        var out: [UInt8] = [start]
        for b in raw {
            if b == start || b == end || b == escape {
                out += [escape, b &- 0x10]
            } else {
                out.append(b)
            }
        }
        out.append(end)
        return out
    }

    /// Decodes one complete frame including its '>' and '<' markers.
    static func unpack(_ frame: ArraySlice<UInt8>) -> Frame? {
        guard frame.count >= 2, frame.first == start, frame.last == end else { return nil }
        var raw: [UInt8] = []
        raw.reserveCapacity(frame.count)
        var it = frame.dropFirst().dropLast().makeIterator()
        while let b = it.next() {
            if b == escape {
                guard let next = it.next() else { return nil }
                raw.append(next &+ 0x10)
            } else {
                raw.append(b)
            }
        }
        guard raw.count >= 7 else { return nil }
        let checksum = raw.removeLast()
        guard raw.reduce(0, &+) == checksum else { return nil }
        let size = Int(raw[2]) << 24 | Int(raw[3]) << 16 | Int(raw[4]) << 8 | Int(raw[5])
        let payload = Array(raw[6...])
        guard payload.count == size else { return nil }
        return Frame(type: raw[0], seq: raw[1], payload: payload)
    }

    /// Accumulates RFCOMM bytes and yields complete frames.
    struct StreamParser {
        private var buffer: [UInt8] = []

        mutating func feed(_ bytes: [UInt8]) -> [Frame] {
            buffer += bytes
            var frames: [Frame] = []
            while true {
                guard let s = buffer.firstIndex(of: start) else { buffer.removeAll(); break }
                if s > 0 { buffer.removeFirst(s) }
                guard let e = buffer.firstIndex(of: end) else { break }
                if let f = unpack(buffer[0...e]) { frames.append(f) }
                buffer.removeFirst(e + 1)
            }
            if buffer.count > 8192 { buffer.removeAll() }
            return frames
        }
    }
}

/// Command bytes (protocol v2, table 1) used by this app.
enum Cmd {
    static let getProtocolInfo: UInt8 = 0x00
    static let retProtocolInfo: UInt8 = 0x01
    static let powerGetStatus: UInt8 = 0x22
    static let powerRetStatus: UInt8 = 0x23
    static let powerNtfyStatus: UInt8 = 0x25
    static let ncAsmGetParam: UInt8 = 0x66
    static let ncAsmRetParam: UInt8 = 0x67
    static let ncAsmSetParam: UInt8 = 0x68
    static let ncAsmNtfyParam: UInt8 = 0x69

    static let powerBattery: UInt8 = 0x00
    /// NC/ASM layouts with [type, changeStatus, totalEffect, mode, ambientMode, level, ...].
    static let ncDualSeamless: UInt8 = 0x17      // WH-1000XM5
    static let ncDualSeamlessNA: UInt8 = 0x19    // same + noise-adaptive fields
}
