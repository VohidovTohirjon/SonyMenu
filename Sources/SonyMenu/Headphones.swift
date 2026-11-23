import Foundation
import IOBluetooth

enum SoundMode: Equatable {
    case noiseCancelling, ambient, off
}

/// Finds the paired Sony headphones, keeps an RFCOMM channel to them while they are
/// connected, and exposes battery and NC/ambient state.
@MainActor
final class Headphones: NSObject, ObservableObject {
    // Audio link is up (the menu bar icon is shown).
    @Published var isPresent = false
    // Control channel is open and the headphones have answered.
    @Published private(set) var isReady = false
    @Published private(set) var name = "Наушники"
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var mode: SoundMode?
    @Published var ambientLevel: Double = 10
    @Published private(set) var focusOnVoice = false
    @Published private(set) var problem: String?

    var log: (String) -> Void = { _ in }

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNote: IOBluetoothUserNotification?
    private var parser = MDR.StreamParser()

    private var seq: UInt8 = 0
    private var queue: [[UInt8]] = []
    private var awaitingAck = false
    private var ackToken = 0

    private var ncType: UInt8 = Cmd.ncDualSeamless
    private var lastNcParams: [UInt8]?
    private var openAttempts = 0
    private var batteryTimer: Timer?

    private let serviceUUID: IOBluetoothSDPUUID = {
        let hex = MDR.serviceUUID.replacingOccurrences(of: "-", with: "")
        var bytes = [UInt8]()
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            bytes.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return IOBluetoothSDPUUID(bytes: bytes, length: bytes.count)
    }()

    // MARK: - Lifecycle

    func start() {
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceDidConnect(_:device:)))
        if let d = findSonyDevice(connectedOnly: true) {
            attach(d)
        } else {
            log("Наушники не подключены, жду подключения")
        }
    }

    private func findSonyDevice(connectedOnly: Bool) -> IOBluetoothDevice? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.first { d in
            (!connectedOnly || d.isConnected()) && d.getServiceRecord(for: serviceUUID) != nil
        }
    }

    @objc private func deviceDidConnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.getServiceRecord(for: serviceUUID) != nil else { return }
        attach(device)
    }

    @objc private func deviceDidDisconnect(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard device.addressString == self.device?.addressString else { return }
        log("Наушники отключились")
        detach()
    }

    private func attach(_ d: IOBluetoothDevice) {
        if device?.addressString == d.addressString, channel != nil { return }
        device = d
        name = d.name ?? "Наушники"
        isPresent = true
        problem = nil
        disconnectNote?.unregister()
        disconnectNote = d.register(forDisconnectNotification: self,
                                    selector: #selector(deviceDidDisconnect(_:device:)))
        openAttempts = 0
        // Give the audio profiles a moment to settle before opening the control channel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.openChannel() }
    }

    private func detach() {
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        disconnectNote?.unregister()
        disconnectNote = nil
        device = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        queue.removeAll()
        awaitingAck = false
        seq = 0
        parser = MDR.StreamParser()
        lastNcParams = nil
        isReady = false
        isPresent = false
        battery = nil
        mode = nil
    }

    private func openChannel() {
        guard let d = device, channel == nil else { return }
        openAttempts += 1
        guard let record = d.getServiceRecord(for: serviceUUID) else {
            problem = "Наушники не отвечают"
            return
        }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else {
            problem = "Не нашёл канал управления"
            return
        }
        var ch: IOBluetoothRFCOMMChannel?
        let result = d.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
        if result != kIOReturnSuccess {
            log("Не открылся канал: \(String(format: "0x%x", result))")
            retryOpen()
            return
        }
        channel = ch
        log("Открываю канал \(channelID)")
    }

    private func retryOpen() {
        channel = nil
        guard openAttempts < 4, device != nil else {
            problem = "Не удалось подключиться к управлению"
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.openChannel() }
    }

    fileprivate func channelOpened(_ ch: IOBluetoothRFCOMMChannel, status: IOReturn) {
        guard ch === channel else { return }
        guard status == kIOReturnSuccess else {
            log("Канал не открылся: \(String(format: "0x%x", status))")
            retryOpen()
            return
        }
        log("Канал открыт")
        send([Cmd.getProtocolInfo, 0x00])
        // Some firmwares answer only after the handshake; ask for state right after it anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.channel != nil, !self.isReady else { return }
            self.requestState()
        }
    }

    fileprivate func channelClosed(_ ch: IOBluetoothRFCOMMChannel) {
        guard ch === channel else { return }
        log("Канал закрыт")
        channel = nil
        isReady = false
        if device?.isConnected() == true { retryOpen() } else { detach() }
    }

    // MARK: - Sending

    private func send(_ payload: [UInt8]) {
        queue.append(payload)
        pump()
    }

    private func pump() {
        guard !awaitingAck, channel != nil, !queue.isEmpty else { return }
        let payload = queue.removeFirst()
        write(MDR.pack(type: .dataMDR, seq: seq, payload: payload))
        awaitingAck = true
        ackToken += 1
        let token = ackToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.awaitingAck, self.ackToken == token else { return }
            self.awaitingAck = false
            self.pump()
        }
    }

    private func write(_ bytes: [UInt8]) {
        guard let ch = channel else { return }
        var data = bytes
        let r = data.withUnsafeMutableBytes { ptr in
            ch.writeSync(ptr.baseAddress, length: UInt16(ptr.count))
        }
        if r != kIOReturnSuccess { log("Ошибка записи: \(String(format: "0x%x", r))") }
    }

    // MARK: - Receiving

    fileprivate func received(_ bytes: [UInt8]) {
        for frame in parser.feed(bytes) {
            switch frame.type {
            case MDR.DataType.ack.rawValue:
                seq = 1 &- seq
                awaitingAck = false
                pump()
            case MDR.DataType.dataMDR.rawValue, MDR.DataType.dataMDRNo2.rawValue:
                write(MDR.pack(type: .ack, seq: 1 &- frame.seq, payload: []))
                if frame.type == MDR.DataType.dataMDR.rawValue { handle(frame.payload) }
            default:
                break
            }
        }
    }

    private func handle(_ p: [UInt8]) {
        guard let cmd = p.first else { return }
        switch cmd {
        case Cmd.retProtocolInfo:
            log("Протокол: \(p.count >= 6 ? String(p[2...5].reduce(0) { $0 << 8 | Int($1) }, radix: 16) : "?")")
            requestState()
        case Cmd.powerRetStatus, Cmd.powerNtfyStatus:
            guard p.count >= 4, p[1] == Cmd.powerBattery else { return }
            battery = Int(p[2])
            charging = p[3] == 0x01
            isReady = true
            log("Батарея: \(p[2])%\(charging ? ", заряжается" : "")")
        case Cmd.ncAsmRetParam, Cmd.ncAsmNtfyParam:
            guard p.count >= 7, p[1] == Cmd.ncDualSeamless || p[1] == Cmd.ncDualSeamlessNA else {
                log("Неизвестный формат шумоподавления: \(p.map { String(format: "%02x", $0) }.joined())")
                return
            }
            ncType = p[1]
            lastNcParams = p
            mode = p[3] == 0 ? .off : (p[4] == 0 ? .noiseCancelling : .ambient)
            focusOnVoice = p[5] == 0x01
            if p[6] > 0 { ambientLevel = Double(p[6]) }
            isReady = true
            log("Режим: \(mode.map { "\($0)" } ?? "?"), уровень \(p[6]), голос \(focusOnVoice)")
        default:
            break
        }
    }

    private func requestState() {
        send([Cmd.powerGetStatus, Cmd.powerBattery])
        send([Cmd.ncAsmGetParam, ncType])
        // If the headphones use the noise-adaptive layout, the first request goes unanswered.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.channel != nil, self.lastNcParams == nil else { return }
            self.ncType = Cmd.ncDualSeamlessNA
            self.send([Cmd.ncAsmGetParam, self.ncType])
        }
        if batteryTimer == nil {
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.send([Cmd.powerGetStatus, Cmd.powerBattery]) }
            }
        }
    }

    /// Sample state for `--snapshot` renders.
    func loadSampleState(mode: SoundMode) {
        name = "WH-1000XM5"
        battery = 85
        mode == .ambient ? (charging = false) : (charging = true)
        self.mode = mode
        ambientLevel = 14
        focusOnVoice = true
        isPresent = true
        isReady = true
    }

    // MARK: - Controls

    func setMode(_ newMode: SoundMode) {
        mode = newMode
        sendNc()
    }

    func setFocusOnVoice(_ on: Bool) {
        focusOnVoice = on
        sendNc()
    }

    /// Call when the level slider is released.
    func commitAmbientLevel() {
        sendNc()
    }

    private func sendNc() {
        guard let mode else { return }
        var p = lastNcParams ?? [Cmd.ncAsmRetParam, ncType, 0x01, 0x01, 0x00, 0x00, 0x0A]
        if p[1] == Cmd.ncDualSeamlessNA && p.count < 9 { p += [0x00, 0x00] }
        p[0] = Cmd.ncAsmSetParam
        p[2] = 0x01                                   // value changed (not dragging)
        p[3] = mode == .off ? 0x00 : 0x01             // NC/ASM on
        if mode != .off { p[4] = mode == .ambient ? 0x01 : 0x00 }
        p[5] = focusOnVoice ? 0x01 : 0x00
        p[6] = UInt8(max(1, min(20, ambientLevel.rounded())))
        var stored = p
        stored[0] = Cmd.ncAsmRetParam
        lastNcParams = stored
        send(p)
    }
}

extension Headphones: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated { channelOpened(rfcommChannel, status: error) }
    }

    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                       data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        MainActor.assumeIsolated { received(bytes) }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated { channelClosed(rfcommChannel) }
    }
}
