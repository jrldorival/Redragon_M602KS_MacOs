// Redragon M602-KS — percentual da bateria na barra de menus do macOS.
//
// Protocolo extraído do software oficial para Windows (OemDrv.exe, rotina que gera o log "ReadPower"):
//   - receptor VID 0x258A, PID 0x002E/0x002F, coleção HID de fabricante (UsagePage 0xFF00, Usage 0x01)
//     com feature report de 8 bytes e Report ID 5;
//   - envia SetFeature [05 90 00 00 00 00 00 00] e, depois de ~20 ms, lê GetFeature do report 5;
//   - resposta: byte 2 = 0x10 (no cabo) ou 0x11 (sem fio); byte 3 = percentual da bateria quando sem fio.
//     No cabo o byte 3 não é o percentual (vem 1), e o software oficial também o ignora nesse caso.
//   - O receptor responde mesmo com o mouse desligado, repetindo o último valor; o software oficial não detecta isso.
//
// Configuração (rotinas "FindDev" e "Apply_24G" do mesmo executável):
//   - identificação: comando 0x01 no report 5; a resposta traz 4 bytes que o software confere com o PSD do Cfg.ini;
//   - leitura do bloco General (DPI, LED, taxa): comando 0x11 (PID 0x002E) ou 0x21 (PID 0x002F) no report 5,
//     e a resposta vem no feature report 8, de 520 bytes, com os 146 bytes do bloco a partir do byte 8;
//   - gravação: feature report 8 = [08, comando, 00, 92, 00, 00, 00, 00] + os 146 bytes (mesmo comando da leitura);
//   - botões: feature report 8 = [08, comando + 1, 00, 50, 00, 00, 00, 00] + 20 × 4 bytes + A5 (rotina "SetMatrix"),
//     sem comando de leitura.

import AppKit
import IOKit.hid

private let vendorID = 0x258A
private let productIDs = [0x002E, 0x002F]
private let reportID: UInt8 = 0x05
private let reportSize = 8
private let cmdReadPower: UInt8 = 0x90
private let statusCable: UInt8 = 0x10
private let statusWireless: UInt8 = 0x11
private let cmdIdentify: UInt8 = 0x01
// Resposta da identificação, bytes 2 a 5: "2880", o PSD do Cfg.ini que o software oficial confere antes de gravar.
private let expectedIdentity: [UInt8] = [0x32, 0x38, 0x38, 0x30]
private let configReportID: UInt8 = 0x08
private let configReportSize = 520
// Bloco General: 146 bytes, começa com 0x64 e tem 0xA5 no byte 144.
let generalSize = 146
// Matriz de botões: 20 posições de 4 bytes.
let buttonSlots = 20

// Coleção que recebe o comando, coleção que devolve o bloco de 520 bytes e o comando de leitura do bloco General.
private typealias ConfigLink = (cmd: IOHIDDevice, data: IOHIDDevice, command: UInt8)
// Quantas leituras sem fio entram na mediana exibida (uma por minuto, mais as de "Atualizar agora").
private let medianWindow = 5

private extension Notification.Name {
    static let mouseDevicesChanged = Notification.Name("mouseDevicesChanged")
}

/// Texto da interface no idioma do macOS: a chave é o texto em inglês, e Localization/pt-BR.lproj traz o português.
func tr(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

struct Reading {
    let level: Int
    let onCable: Bool
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let stateItem = NSMenuItem(title: tr("Looking for the mouse…"), action: nil, keyEquivalent: "")
    private let rawItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var managerOpen = false
    private var recentLevels: [Int] = []
    private var settings: SettingsWindowController?
    private var buttonsWindow: ButtonsWindowController?

    var backupFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RedragonBattery", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(rawItem)
        menu.addItem(.separator())
        let refreshItem = NSMenuItem(title: tr("Refresh now"), action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        let settingsItem = NSMenuItem(title: tr("Mouse settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let buttonsItem = NSMenuItem(title: tr("Mouse buttons…"), action: #selector(openButtons), keyEquivalent: "")
        buttonsItem.target = self
        menu.addItem(buttonsItem)
        let backupItem = NSMenuItem(title: tr("Save settings backup…"), action: #selector(saveConfigBackup), keyEquivalent: "")
        backupItem.target = self
        menu.addItem(backupItem)
        let privacyItem = NSMenuItem(title: tr("Open Input Monitoring…"), action: #selector(openPrivacySettings), keyEquivalent: "")
        privacyItem.target = self
        menu.addItem(privacyItem)
        menu.addItem(.separator())
        // A versão vem do arquivo VERSION, que o build.sh grava no Info.plist.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        menu.addItem(NSMenuItem(title: "Redragon Battery \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: tr("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        show(text: "…", state: tr("Looking for the mouse…"), raw: "")

        // No macOS a coleção de fabricante nem sempre é a principal da interface, então casa por qualquer par de usage.
        let matching = productIDs.map { pid -> [String: Any] in
            [kIOHIDVendorIDKey: vendorID,
             kIOHIDProductIDKey: pid,
             kIOHIDDeviceUsagePageKey: 0xFF00,
             kIOHIDDeviceUsageKey: 0x01]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        // Async para não reentrar no refresh() enquanto o IOHIDManagerOpen ainda está entregando os dispositivos.
        let notify: IOHIDDeviceCallback = { _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mouseDevicesChanged, object: nil)
            }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, notify, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, notify, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        // O receptor também se apresenta como teclado (macros), então o macOS exige Monitoramento de Entrada para abri-lo.
        // Sem o certificado do criar-certificado.sh a assinatura muda a cada compilação e a permissão precisa ser dada de novo.
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .mouseDevicesChanged, object: nil)
        // O mouse não avisa quando a bateria muda; o software oficial também pergunta de tempos em tempos.
        Timer.scheduledTimer(timeInterval: 60, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        refresh()
    }

    @objc private func refresh() {
        if !managerOpen {
            let opened = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard opened == kIOReturnSuccess else {
                let reason = opened == kIOReturnNotPermitted ? tr("No Input Monitoring permission") : tr("No access to the receiver")
                show(text: "!", state: String(format: "%@ (0x%08X)", reason, opened), raw: "")
                return
            }
            managerOpen = true
        }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            show(text: "–", state: tr("Receiver not found"), raw: "")
            return
        }
        // Com o cabo, o mouse pode aparecer como um segundo dispositivo além do receptor (PID 0x002E e 0x002F):
        // consulta todos e mostra a resposta de cada um, identificada pelo PID.
        var readings: [Reading] = []
        var raws: [String] = []
        for device in devices.sorted(by: { featureSize($0) == reportSize && featureSize($1) != reportSize }) {
            let pid = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let result = readPower(device)
            raws.append(String(format: "%04lX: ", pid) + result.raw)
            if let reading = result.reading {
                readings.append(reading)
            }
        }
        let raw = raws.joined(separator: "  |  ")
        let onCable = readings.contains { $0.onCable }

        // No cabo o mouse responde 0x10 com 1 no lugar do percentual, e o receptor continua respondendo 0x11 com o último
        // percentual sem fio, parado (testado: 37% por 20 minutos carregando). Então no cabo não há carga para mostrar.
        if onCable {
            // Carregando, o percentual muda de verdade; a mediana recomeça quando o cabo sair.
            recentLevels.removeAll()
            let last = readings.first(where: { !$0.onCable }).map { String(format: tr(" (last wireless reading: %ld%%)"), $0.level) } ?? ""
            show(text: "", charging: true, state: tr("On cable — the mouse does not report the charge while charging") + last, raw: raw)
            return
        }
        // Só a resposta "sem fio" (0x11) traz o percentual.
        guard let wireless = readings.first(where: { !$0.onCable }) else {
            show(text: "?", state: tr("No response from the mouse (off or asleep?)"), raw: raw)
            return
        }
        // O mouse oscila alguns pontos entre uma leitura e outra (37 → 39 → 37); a mediana segura o número exibido.
        recentLevels.append(wireless.level)
        if recentLevels.count > medianWindow {
            recentLevels.removeFirst()
        }
        let level = recentLevels.sorted()[recentLevels.count / 2]
        let detail = level == wireless.level ? "" : String(format: tr(" (current reading: %ld%%)"), wireless.level)
        show(text: "\(level)%", percent: level, state: String(format: tr("Wireless — %ld%%"), level) + detail, raw: raw)
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(mouse: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        settings?.showWindow(nil)
        settings?.reload()
    }

    @objc private func openButtons() {
        if buttonsWindow == nil {
            buttonsWindow = ButtonsWindowController(mouse: self)
        }
        NSApp.activate(ignoringOtherApps: true)
        buttonsWindow?.showWindow(nil)
    }

    @objc private func saveConfigBackup() {
        let result = readGeneral()
        guard let block = result.block else {
            alert(tr("Could not read the settings"), result.error ?? "")
            return
        }
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try saveBackup(block: block)])
        } catch {
            alert(tr("Could not save the backup"), error.localizedDescription)
        }
    }

    /// Salva o bloco General em .bin (para restaurar) e em .txt (para ler); devolve o .bin.
    func saveBackup(block: [UInt8]) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = backupFolder.appendingPathComponent("general-\(formatter.string(from: Date()))")
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let bin = base.appendingPathExtension("bin")
        try Data(block).write(to: bin)
        let lines = stride(from: 0, to: block.count, by: 16).map { offset in
            String(format: "%03lX: ", offset) + hex(Array(block[offset..<min(offset + 16, block.count)]))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
        return bin
    }

    /// Lê o bloco General (146 bytes); em caso de falha devolve a mensagem de erro.
    func readGeneral() -> (block: [UInt8]?, error: String?) {
        guard let link = configLink() else {
            return (nil, tr("Receiver not found. Connect the receiver and turn the mouse on."))
        }
        let response = request(link.command, via: link.cmd, answer: link.data, id: configReportID, size: configReportSize)
        guard response.sent == kIOReturnSuccess, response.result == kIOReturnSuccess,
              response.bytes.count >= 8 + generalSize, response.bytes[1] == link.command else {
            return (nil, String(format: tr("Read failed (send 0x%08X, read 0x%08X)."), response.sent, response.result))
        }
        let block = Array(response.bytes[8..<8 + generalSize])
        guard block[0] == 0x64, block[144] == 0xA5 else {
            return (nil, tr("The settings read from the mouse have an unexpected format."))
        }
        return (block, nil)
    }

    /// Grava o bloco General e lê de volta para conferir; devolve a mensagem de erro, ou nil se o mouse ficou exatamente com o bloco gravado.
    func writeGeneral(_ block: [UInt8]) -> String? {
        guard block.count == generalSize, block[0] == 0x64, block[144] == 0xA5 else {
            return tr("Invalid settings; nothing was written.")
        }
        let target = writableLink()
        guard let link = target.link else {
            return target.error
        }

        var report = [UInt8](repeating: 0, count: configReportSize)
        report[0] = configReportID
        report[1] = link.command
        report[3] = UInt8(generalSize)
        report.replaceSubrange(8..<8 + generalSize, with: block)
        let sent = IOHIDDeviceSetReport(link.data, kIOHIDReportTypeFeature, CFIndex(configReportID), report, report.count)
        guard sent == kIOReturnSuccess else {
            return String(format: tr("Write failed (0x%08X)."), sent)
        }

        let check = readGeneral()
        guard let saved = check.block else {
            return tr("Written, but could not read it back to verify:") + " " + (check.error ?? "")
        }
        return saved == block ? nil : tr("The mouse does not match what was written. Restore the backup.")
    }

    /// Grava a matriz de botões (20 posições de 4 bytes); devolve a mensagem de erro, ou nil.
    /// O mouse não tem comando para ler a matriz, então não há conferência depois da gravação.
    func writeButtons(_ slots: [UInt32]) -> String? {
        guard slots.count == buttonSlots else {
            return tr("Invalid button layout; nothing was written.")
        }
        let target = writableLink()
        guard let link = target.link else {
            return target.error
        }

        // Mesmo modo do bloco General, um comando acima: 0x12 (PID 0x002E) ou 0x22 (PID 0x002F).
        var report = [UInt8](repeating: 0, count: configReportSize)
        report[0] = configReportID
        report[1] = link.command + 1
        report[3] = UInt8(buttonSlots * 4)
        for (index, slot) in slots.enumerated() {
            for byte in 0..<4 {
                report[8 + index * 4 + byte] = UInt8(truncatingIfNeeded: slot >> (8 * byte))
            }
        }
        report[8 + buttonSlots * 4] = 0xA5
        let sent = IOHIDDeviceSetReport(link.data, kIOHIDReportTypeFeature, CFIndex(configReportID), report, report.count)
        return sent == kIOReturnSuccess ? nil : String(format: tr("Write failed (0x%08X)."), sent)
    }

    // Antes de gravar, confere a identificação como o software oficial faz ("Psd unmatched").
    private func writableLink() -> (link: ConfigLink?, error: String?) {
        guard let link = configLink() else {
            return (nil, tr("Receiver not found; nothing was written."))
        }
        let identity = request(cmdIdentify, via: link.cmd, answer: link.cmd, id: reportID, size: reportSize)
        guard identity.bytes.count >= 6, Array(identity.bytes[2..<6]) == expectedIdentity else {
            return (nil, tr("The device did not identify itself as an M602-KS; nothing was written."))
        }
        return (link, nil)
    }

    // No Windows o pedido vai pela coleção de 8 bytes e o bloco volta pela de 520; no macOS podem ser a mesma interface.
    // O software oficial escolhe o comando pelo PID: 0x002E → 0x11, 0x002F → 0x21.
    private func configLink() -> ConfigLink? {
        guard managerOpen, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let anyDevice = devices.first else {
            return nil
        }
        let cmd = devices.first(where: { featureSize($0) == reportSize }) ?? anyDevice
        let data = devices.first(where: { featureSize($0) >= configReportSize }) ?? cmd
        let pid = IOHIDDeviceGetProperty(cmd, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return (cmd, data, pid == 0x002F ? 0x21 : 0x11)
    }

    private func readPower(_ device: IOHIDDevice) -> (reading: Reading?, raw: String) {
        let sent = sendCommand(device, cmdReadPower)
        guard sent == kIOReturnSuccess else {
            return (nil, String(format: tr("SetFeature failed (0x%08X)"), sent))
        }

        var raw = ""
        // Não há evento de "resposta pronta": o software oficial espera 20 ms e lê. Aqui a leitura se repete até vir um status válido.
        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.02)
            let response = getFeature(device, id: reportID, size: reportSize)
            guard response.result == kIOReturnSuccess else {
                raw = String(format: tr("GetFeature failed (0x%08X)"), response.result)
                continue
            }
            let bytes = response.bytes
            raw = hex(bytes)
            guard bytes.count >= 4 else { continue }
            let status = bytes[2]
            if status == statusCable || status == statusWireless {
                return (Reading(level: Int(bytes[3]), onCable: status == statusCable), raw)
            }
        }
        return (nil, raw)
    }

    // Comando de 8 bytes no report 5: [05, comando, 0, 0, 0, 0, 0, 0].
    private func sendCommand(_ device: IOHIDDevice, _ command: UInt8) -> IOReturn {
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = reportID
        report[1] = command
        return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), report, report.count)
    }

    // Sem evento de "resposta pronta": consulta até a resposta trazer o comando de volta no byte 1, com limite de tentativas.
    private func request(_ command: UInt8, via cmdDevice: IOHIDDevice, answer dataDevice: IOHIDDevice, id: UInt8, size: Int) -> (sent: IOReturn, result: IOReturn, bytes: [UInt8]) {
        let sent = sendCommand(cmdDevice, command)
        guard sent == kIOReturnSuccess else { return (sent, sent, []) }
        var response = getFeature(dataDevice, id: id, size: size)
        var attempts = 0
        while attempts < 10 && (response.result != kIOReturnSuccess || response.bytes.count < 2 || response.bytes[1] != command) {
            Thread.sleep(forTimeInterval: 0.02)
            response = getFeature(dataDevice, id: id, size: size)
            attempts += 1
        }
        return (sent, response.result, response.bytes)
    }

    private func getFeature(_ device: IOHIDDevice, id: UInt8, size: Int) -> (result: IOReturn, bytes: [UInt8]) {
        var report = [UInt8](repeating: 0, count: size)
        var length = CFIndex(size)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(id), &report, &length)
        return (result, Array(report.prefix(result == kIOReturnSuccess ? length : 0)))
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func featureSize(_ device: IOHIDDevice) -> Int {
        IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    // percent preenche a bateria desenhada na barra; sem ele a bateria fica vazia (no cabo ou sem leitura).
    private func show(text: String, percent: Int? = nil, charging: Bool = false, state: String, raw: String) {
        stateItem.title = state
        rawItem.title = tr("Response:") + " " + raw
        rawItem.isHidden = raw.isEmpty
        guard let button = statusItem.button else { return }

        // Mouse + bateria em preto, como template: o macOS pinta na cor da barra de menus (clara ou escura).
        let mouse = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        let mouseWidth = mouse.map { $0.size.width + 3 } ?? 0
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: mouseWidth + 25, height: height), flipped: false) { _ in
            NSColor.black.set()
            if let mouse {
                mouse.draw(in: NSRect(x: 0, y: (height - mouse.size.height) / 2, width: mouse.size.width, height: mouse.size.height))
            }
            let body = NSRect(x: mouseWidth + 0.5, y: 3.5, width: 21, height: 9)
            let outline = NSBezierPath(roundedRect: body, xRadius: 2.5, yRadius: 2.5)
            outline.lineWidth = 1
            outline.stroke()
            NSBezierPath(roundedRect: NSRect(x: body.maxX + 1, y: body.midY - 2, width: 1.5, height: 4), xRadius: 0.75, yRadius: 0.75).fill()
            if let percent {
                let inner = body.insetBy(dx: 1.5, dy: 1.5)
                let fill = inner.width * CGFloat(min(100, max(0, percent))) / 100
                NSBezierPath(roundedRect: NSRect(x: inner.minX, y: inner.minY, width: fill, height: inner.height), xRadius: 1, yRadius: 1).fill()
            }
            if charging {
                let bolt = NSBezierPath()
                bolt.move(to: NSPoint(x: body.midX + 1.5, y: body.maxY + 1))
                bolt.line(to: NSPoint(x: body.midX - 3, y: body.midY - 0.5))
                bolt.line(to: NSPoint(x: body.midX - 0.3, y: body.midY - 0.5))
                bolt.line(to: NSPoint(x: body.midX - 1.5, y: body.minY - 1))
                bolt.line(to: NSPoint(x: body.midX + 3, y: body.midY + 0.5))
                bolt.line(to: NSPoint(x: body.midX + 0.3, y: body.midY + 0.5))
                bolt.close()
                bolt.fill()
            }
            return true
        }
        image.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = text.isEmpty ? "" : " \(text)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
