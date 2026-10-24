// Janela de configurações: taxa de resposta, níveis de DPI com suas cores e efeito de LED, todos no bloco General.
//
// Campos do bloco (confirmados com a leitura de um M602-KS de fábrica):
//   byte 2   nibble baixo = taxa (1 = 125, 2 = 250, 3 = 500, 4 = 1000 Hz)
//   byte 3   nibble alto = nível ativo (a partir de 1), nibble baixo = quantidade de níveis
//   5–20     8 posições de DPI, 2 bytes cada (little endian), código = DPI ÷ 250
//   37–60    cor RGB de cada nível, em sequência
//   61       efeito de LED (1 a 9; 0 = desligado)
//   62–133   um byte de parâmetros por efeito: nibble alto = brilho (1–4), nibble baixo = velocidade (1–3);
//            byte 63 = sentido do Colorful Streaming; 65–67 = cor do Steady.
//            As faixas vêm dos controles da janela de LED do software oficial (4 e 3 posições) e batem
//            com os valores de fábrica (brilho 4, velocidade 2). Testado no mouse: 3 = mais rápido, 4 = mais forte.

import AppKit

private let rates: [(code: UInt8, hz: Int)] = [(1, 125), (2, 250), (3, 500), (4, 1000)]
// O software oficial oferece 5 níveis (DM=5 no Cfg.ini); o bloco tem espaço para 8.
private let maxLevels = 5
private let dpiSlots = 8
private let dpiStep = 250
private let dpiValues = Array(stride(from: dpiStep, through: 8000, by: dpiStep))
// Nomes em inglês do text.xml do software oficial (tc_led_mode1 a tc_led_mode10); o último é gravado como 0.
private let effects = ["Colorful Streaming", "Steady", "Breathing", "Colorful Tail", "Neon", "Colorful Steady", "Flicker", "Stars Twinkle", "Wave", "Off"].map(tr)
// Na mesma ordem: byte de parâmetros de cada efeito no bloco e o que o software oficial deixa mudar nele (LedOpt1 a LedOpt10 do Cfg.ini).
private let effectParams: [(offset: Int, speed: Bool, brightness: Bool)] = [
    (62, true, false), (64, false, true), (68, true, false), (91, true, false), (92, true, false),
    (93, false, false), (124, false, false), (131, true, false), (132, true, false), (133, false, false),
]
private let streamingDirection = 63
private let steadyColor = 65

final class SettingsWindowController: NSWindowController {
    private unowned let mouse: AppDelegate
    private var block: [UInt8] = []
    private let ratePopup = NSPopUpButton()
    private let levelCountPopup = NSPopUpButton()
    private let activeLevelPopup = NSPopUpButton()
    private var dpiPopups: [NSPopUpButton] = []
    private var colorWells: [NSColorWell] = []
    private let effectPopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let brightnessPopup = NSPopUpButton()
    private let directionCheck = NSButton(checkboxWithTitle: tr("From the tip backwards"), target: nil, action: nil)
    private let steadyColorWell = NSColorWell()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: tr("Apply"), target: nil, action: nil)

    init(mouse: AppDelegate) {
        self.mouse = mouse
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("Mouse settings")
        window.isReleasedWhenClosed = false
        super.init(window: window)

        ratePopup.addItems(withTitles: rates.map { "\($0.hz) Hz" })
        levelCountPopup.addItems(withTitles: (1...maxLevels).map { "\($0)" })
        levelCountPopup.target = self
        levelCountPopup.action = #selector(levelCountChanged)
        effectPopup.addItems(withTitles: effects)
        effectPopup.target = self
        effectPopup.action = #selector(updateEffectControls)
        speedPopup.addItems(withTitles: [tr("1 (slow)"), "2", tr("3 (fast)")])
        brightnessPopup.addItems(withTitles: [tr("1 (dim)"), "2", "3", tr("4 (bright)")])
        steadyColorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        steadyColorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        var rows: [[NSView]] = [
            [NSTextField(labelWithString: tr("Polling rate")), ratePopup],
            [NSTextField(labelWithString: tr("DPI levels")), levelCountPopup],
            [NSTextField(labelWithString: tr("Active level")), activeLevelPopup],
        ]
        for level in 1...maxLevels {
            let dpiPopup = NSPopUpButton()
            dpiPopup.addItems(withTitles: dpiValues.map { "\($0) DPI" })
            let well = NSColorWell()
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
            dpiPopups.append(dpiPopup)
            colorWells.append(well)
            rows.append([NSTextField(labelWithString: String(format: tr("Level %ld"), level)), NSStackView(views: [dpiPopup, well])])
        }
        rows.append([NSTextField(labelWithString: tr("Lighting effect")), effectPopup])
        rows.append([NSTextField(labelWithString: tr("Speed")), speedPopup])
        rows.append([NSTextField(labelWithString: tr("Brightness")), brightnessPopup])
        rows.append([NSTextField(labelWithString: tr("Direction")), directionCheck])
        rows.append([NSTextField(labelWithString: tr("Effect color")), steadyColorWell])
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        applyButton.target = self
        applyButton.action = #selector(apply)
        applyButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            NSButton(title: tr("Read from mouse"), target: self, action: #selector(reload)),
            NSButton(title: tr("Restore backup…"), target: self, action: #selector(restoreBackup)),
            applyButton,
        ])
        statusLabel.preferredMaxLayoutWidth = 420

        let content = NSStackView(views: [grid, statusLabel, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc func reload() {
        let result = mouse.readGeneral()
        guard let block = result.block else {
            self.block = []
            applyButton.isEnabled = false
            statusLabel.stringValue = result.error ?? tr("Read failed.")
            return
        }
        self.block = block

        ratePopup.selectItem(at: rates.firstIndex { $0.code == block[2] & 0x0F } ?? -1)
        let count = Int(block[3] & 0x0F)
        levelCountPopup.selectItem(at: min(max(count, 1), maxLevels) - 1)
        for level in 0..<maxLevels {
            let code = Int(block[5 + 2 * level]) | Int(block[6 + 2 * level]) << 8
            dpiPopups[level].selectItem(at: dpiValues.firstIndex(of: code * dpiStep) ?? -1)
            let c = 37 + 3 * level
            colorWells[level].color = NSColor(srgbRed: CGFloat(block[c]) / 255, green: CGFloat(block[c + 1]) / 255, blue: CGFloat(block[c + 2]) / 255, alpha: 1)
        }
        updateLevelRows(active: Int(block[3] >> 4))
        let effect = Int(block[61])
        effectPopup.selectItem(at: effect == 0 ? effects.count - 1 : (effect < effects.count ? effect - 1 : -1))
        updateEffectControls()

        // Fora do que a janela sabe editar, gravar mudaria o mouse sem a pessoa ver; nesse caso só mostra.
        let editable = (1...maxLevels).contains(count)
        applyButton.isEnabled = editable
        statusLabel.stringValue = editable ? tr("Read from the mouse.") : String(format: tr("The mouse has %ld DPI levels; this window edits 1 to %ld, so it will not write."), count, maxLevels)
    }

    // Mostra o que está gravado para o efeito escolhido e libera só o que o software oficial deixa mudar nele.
    @objc private func updateEffectControls() {
        let index = effectPopup.indexOfSelectedItem
        guard block.count == generalSize, index >= 0 else { return }
        let effect = effectParams[index]
        let speed = Int(block[effect.offset] & 0x0F)
        let brightness = Int(block[effect.offset] >> 4)
        speedPopup.selectItem(at: (1...3).contains(speed) ? speed - 1 : -1)
        brightnessPopup.selectItem(at: (1...4).contains(brightness) ? brightness - 1 : -1)
        speedPopup.isEnabled = effect.speed
        brightnessPopup.isEnabled = effect.brightness
        directionCheck.isEnabled = index == 0
        directionCheck.state = block[streamingDirection] == 1 ? .on : .off
        steadyColorWell.isEnabled = index == 1
        steadyColorWell.color = NSColor(srgbRed: CGFloat(block[steadyColor]) / 255, green: CGFloat(block[steadyColor + 1]) / 255, blue: CGFloat(block[steadyColor + 2]) / 255, alpha: 1)
    }

    @objc private func levelCountChanged() {
        updateLevelRows(active: activeLevelPopup.indexOfSelectedItem + 1)
    }

    private func updateLevelRows(active: Int) {
        let count = levelCountPopup.indexOfSelectedItem + 1
        activeLevelPopup.removeAllItems()
        activeLevelPopup.addItems(withTitles: (1...count).map { "\($0)" })
        activeLevelPopup.selectItem(at: min(max(active, 1), count) - 1)
        for level in 0..<maxLevels {
            dpiPopups[level].isEnabled = level < count
            colorWells[level].isEnabled = level < count
        }
    }

    @objc private func apply() {
        guard block.count == generalSize else { return }
        let count = levelCountPopup.indexOfSelectedItem + 1
        guard ratePopup.indexOfSelectedItem >= 0, effectPopup.indexOfSelectedItem >= 0,
              (0..<count).allSatisfy({ dpiPopups[$0].indexOfSelectedItem >= 0 }) else {
            statusLabel.stringValue = tr("Choose the polling rate, the effect and the DPI of every active level.")
            return
        }

        var updated = block
        updated[2] = (block[2] & 0xF0) | rates[ratePopup.indexOfSelectedItem].code
        updated[3] = UInt8((activeLevelPopup.indexOfSelectedItem + 1) << 4 | count)
        // Posições sem nível ficam zeradas, como o software oficial faz.
        for slot in 0..<dpiSlots {
            let code = slot < count ? dpiValues[dpiPopups[slot].indexOfSelectedItem] / dpiStep : 0
            updated[5 + 2 * slot] = UInt8(code & 0xFF)
            updated[6 + 2 * slot] = UInt8(code >> 8)
        }
        let byte = { (value: CGFloat) in UInt8(max(0, min(255, (value * 255).rounded()))) }
        for level in 0..<count {
            let color = colorWells[level].color.usingColorSpace(.sRGB) ?? .black
            updated[37 + 3 * level] = byte(color.redComponent)
            updated[38 + 3 * level] = byte(color.greenComponent)
            updated[39 + 3 * level] = byte(color.blueComponent)
        }
        let effectIndex = effectPopup.indexOfSelectedItem
        updated[61] = effectIndex == effects.count - 1 ? 0 : UInt8(effectIndex + 1)
        let effect = effectParams[effectIndex]
        if effect.speed, speedPopup.indexOfSelectedItem >= 0 {
            updated[effect.offset] = (updated[effect.offset] & 0xF0) | UInt8(speedPopup.indexOfSelectedItem + 1)
        }
        if effect.brightness, brightnessPopup.indexOfSelectedItem >= 0 {
            updated[effect.offset] = (updated[effect.offset] & 0x0F) | UInt8(brightnessPopup.indexOfSelectedItem + 1) << 4
        }
        if effectIndex == 0 {
            updated[streamingDirection] = directionCheck.state == .on ? 1 : 0
        }
        if effectIndex == 1 {
            let color = steadyColorWell.color.usingColorSpace(.sRGB) ?? .black
            updated[steadyColor] = byte(color.redComponent)
            updated[steadyColor + 1] = byte(color.greenComponent)
            updated[steadyColor + 2] = byte(color.blueComponent)
        }

        guard updated != block else {
            statusLabel.stringValue = tr("Nothing changed.")
            return
        }
        let backup: URL
        do {
            backup = try mouse.saveBackup(block: block)
        } catch {
            statusLabel.stringValue = String(format: tr("Nothing was written: backing up the current settings failed (%@)."), error.localizedDescription)
            return
        }
        if let error = mouse.writeGeneral(updated) {
            statusLabel.stringValue = error + " " + String(format: tr("Backup of the previous settings: %@"), backup.lastPathComponent)
        } else {
            block = updated
            statusLabel.stringValue = String(format: tr("Written and verified. Backup of the previous settings: %@"), backup.lastPathComponent)
        }
    }

    @objc private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.directoryURL = mouse.backupFolder
        panel.message = tr("Choose a .bin backup")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url), data.count == generalSize else {
            statusLabel.stringValue = tr("Invalid file: a .bin backup has 146 bytes.")
            return
        }
        if let error = mouse.writeGeneral([UInt8](data)) {
            statusLabel.stringValue = error
        } else {
            reload()
            statusLabel.stringValue = String(format: tr("Backup %@ restored and verified."), url.lastPathComponent)
        }
    }
}
