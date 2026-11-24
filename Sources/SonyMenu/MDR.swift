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
        case dataMDR = 0x0C     // protocol v2, table 1
        case dataMDRNo2 = 0x0E  // protocol v2, table 2
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

    /// Reads a one-byte length-prefixed string at `i`, advancing `i`.
    static func string(_ p: [UInt8], at i: inout Int) -> String? {
        guard i < p.count else { return nil }
        let n = Int(p[i])
        guard i + 1 + n <= p.count else { return nil }
        let s = String(decoding: p[(i + 1)..<(i + 1 + n)], as: UTF8.self)
        i += 1 + n
        return s
    }
}

/// Command bytes (protocol v2). Every value here was checked against libmdr's generated
/// tables and answered by a WH-1000XM5 on firmware 2.3.1 (see docs/PROTOCOL.md).
enum Cmd {
    // Connect
    static let getProtocolInfo: UInt8 = 0x00
    static let retProtocolInfo: UInt8 = 0x01
    static let getDeviceInfo: UInt8 = 0x04
    static let retDeviceInfo: UInt8 = 0x05
    static let getSupport: UInt8 = 0x06
    static let retSupport: UInt8 = 0x07
    // Common
    static let commonGetStatus: UInt8 = 0x12
    static let commonRetStatus: UInt8 = 0x13
    static let commonNtfyStatus: UInt8 = 0x15
    // Power
    static let powerGetCapability: UInt8 = 0x20
    static let powerRetCapability: UInt8 = 0x21
    static let powerGetStatus: UInt8 = 0x22
    static let powerRetStatus: UInt8 = 0x23
    static let powerSetStatus: UInt8 = 0x24
    static let powerNtfyStatus: UInt8 = 0x25
    static let powerGetParam: UInt8 = 0x26
    static let powerRetParam: UInt8 = 0x27
    static let powerSetParam: UInt8 = 0x28
    static let powerNtfyParam: UInt8 = 0x29
    // EQ / Clear Bass
    static let eqGetCapability: UInt8 = 0x50
    static let eqRetCapability: UInt8 = 0x51
    static let eqGetStatus: UInt8 = 0x52
    static let eqRetStatus: UInt8 = 0x53
    static let eqNtfyStatus: UInt8 = 0x55
    static let eqGetParam: UInt8 = 0x56
    static let eqRetParam: UInt8 = 0x57
    static let eqSetParam: UInt8 = 0x58
    static let eqNtfyParam: UInt8 = 0x59
    // NC / ambient
    static let ncAsmGetParam: UInt8 = 0x66
    static let ncAsmRetParam: UInt8 = 0x67
    static let ncAsmSetParam: UInt8 = 0x68
    static let ncAsmNtfyParam: UInt8 = 0x69
    // Operation log
    static let logSetStatus: UInt8 = 0xC4
    static let logNtfyParam: UInt8 = 0xC9
    // Playback
    static let playGetStatus: UInt8 = 0xA2
    static let playRetStatus: UInt8 = 0xA3
    static let playSetStatus: UInt8 = 0xA4
    static let playNtfyStatus: UInt8 = 0xA5
    static let playGetParam: UInt8 = 0xA6
    static let playRetParam: UInt8 = 0xA7
    static let playSetParam: UInt8 = 0xA8
    static let playNtfyParam: UInt8 = 0xA9
    // General settings (touch panel, multipoint on the XM5)
    static let gsGetCapability: UInt8 = 0xD0
    static let gsRetCapability: UInt8 = 0xD1
    static let gsGetParam: UInt8 = 0xD6
    static let gsRetParam: UInt8 = 0xD7
    static let gsSetParam: UInt8 = 0xD8
    static let gsNtfyParam: UInt8 = 0xD9
    // Audio (connection quality, DSEE)
    static let audioGetParam: UInt8 = 0xE6
    static let audioRetParam: UInt8 = 0xE7
    static let audioSetParam: UInt8 = 0xE8
    static let audioNtfyParam: UInt8 = 0xE9
    // System (speak-to-chat, auto pause, voice assistant)
    static let systemGetCapability: UInt8 = 0xF0
    static let systemRetCapability: UInt8 = 0xF1
    static let systemNtfyStatus: UInt8 = 0xF5
    static let systemGetParam: UInt8 = 0xF6
    static let systemRetParam: UInt8 = 0xF7
    static let systemSetParam: UInt8 = 0xF8
    static let systemNtfyParam: UInt8 = 0xF9
    static let systemGetExtParam: UInt8 = 0xFA
    static let systemRetExtParam: UInt8 = 0xFB
    static let systemSetExtParam: UInt8 = 0xFC
    static let systemNtfyExtParam: UInt8 = 0xFD
    // Table 2: voice guidance
    static let t2VoiceGuidanceGetParam: UInt8 = 0x46
    static let t2VoiceGuidanceRetParam: UInt8 = 0x47
    static let t2VoiceGuidanceSetParam: UInt8 = 0x48
    static let t2VoiceGuidanceNtfyParam: UInt8 = 0x49

    // Inquired types
    static let powerBattery: UInt8 = 0x00
    static let powerOff: UInt8 = 0x03
    static let powerAutoOffWearing: UInt8 = 0x05
    /// NC/ASM layouts with [type, changeStatus, totalEffect, mode, ambientMode, level, ...].
    static let ncDualSeamless: UInt8 = 0x17      // WH-1000XM5
    static let ncDualSeamlessNA: UInt8 = 0x19    // same + noise-adaptive fields
    static let ncAmbToggle: UInt8 = 0x30         // what the left NC/AMB button cycles
    static let codecInquiry: UInt8 = 0x02
    static let gsTouchPanel: UInt8 = 0xD1
    static let gsMultipoint: UInt8 = 0xD2
    static let audioConnection: UInt8 = 0x00
    static let audioUpscaling: UInt8 = 0x01
    static let sysAutoPause: UInt8 = 0x01
    static let sysVoiceAssistant: UInt8 = 0x04
    static let sysSpeakToChat: UInt8 = 0x0C
    static let playController: UInt8 = 0x01
    static let playVolume: UInt8 = 0x20
    static let vgOnOff: UInt8 = 0x01
}

/// Table 1 support-function ids the app checks before sending anything.
enum Fn {
    static let codec: UInt8 = 0x12
    static let powerOff: UInt8 = 0x23
    static let autoPowerOffWearing: UInt8 = 0x25
    static let gs1: UInt8 = 0xD1
    static let gs2: UInt8 = 0xD2
    static let presetEq: UInt8 = 0x50
    static let ncDual: UInt8 = 0x6B
    static let ncButton: UInt8 = 0x69
    static let playback: UInt8 = 0xA1
    static let timeSeriesLog: UInt8 = 0xC2
    static let connectionMode: UInt8 = 0xE1
    static let dsee: UInt8 = 0xE2
    static let voiceAssistant: UInt8 = 0xF4
    static let autoPause: UInt8 = 0xF1
    static let speakToChat: UInt8 = 0xFC
    // Table 2
    static let t2VoiceGuidance: UInt8 = 0x41
}
