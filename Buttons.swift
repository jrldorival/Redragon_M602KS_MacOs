// Janela dos botões: o que cada um dos 7 botões programáveis faz.
//
// Matriz de 20 posições de 4 bytes (rotinas keyinfo_to_hardware_code e SetMatrix do OemDrv.exe). A posição de cada
// botão é o 4º número das chaves K<n>_1 do Cfg.ini, e o Cfg.ini tem 7 marcadores de botão (Mark1 a Mark7).
// O mouse não deixa ler a matriz: o app guarda o que gravou em botoes.json e, sem esse arquivo, mostra o padrão de fábrica.

import AppKit

// Padrão de fábrica do Cfg.ini (K1_1 a K10_1 já convertidos); as posições sem chave ficam com 0x0150, como o software oficial faz.
private let factorySlots: [UInt32] = [0x0111, 0x0211, 0x0411, 0x0811, 0x1011, 0x0141, 0x0241, 0x0450] + Array(repeating: UInt32(0x0150), count: 12)
// Posição 6 = botão de cima perto do scroll (Mark6 do Cfg.ini fica ao lado do Mark3, o scroll); posição 7 = o de trás.
// De fábrica o da frente aumenta o DPI e o de trás diminui, conferido no mouse.
private let buttonNames = ["Esquerdo", "Direito", "Meio (scroll)", "Lateral: voltar", "Lateral: avançar", "Superior, perto do scroll", "Superior, atrás"]
private let leftClick: UInt32 = 0x0111
private let functions: [(title: String, code: UInt32)] = [
    ("Clique esquerdo", leftClick), ("Clique direito", 0x0211), ("Clique do meio", 0x0411),
    ("Voltar", 0x0811), ("Avançar", 0x1011), ("Rolar para cima", 0x0112), ("Rolar para baixo", 0xFF12),
    ("Aumentar DPI", 0x0141), ("Diminuir DPI", 0x0241),
]
// Atalho de teclado: [0x21, modificadores, tecla, 0], com modificadores e tecla em códigos HID.
private let shortcutType: UInt32 = 0x21
private let modifiers: [(title: String, bit: UInt32)] = [("⌃", 0x01), ("⇧", 0x02), ("⌥", 0x04), ("⌘", 0x08)]
// Códigos de uso HID do teclado (tabela 0x07).
private let keys: [(title: String, code: UInt32)] = {
    var list: [(title: String, code: UInt32)] = []
    for letter in 0..<26 {
        list.append((title: String(Character(Unicode.Scalar(UInt8(65 + letter)))), code: UInt32(0x04 + letter)))
    }
    for digit in 1...9 {
        list.append((title: "\(digit)", code: UInt32(0x1D + digit)))
    }
    list.append((title: "0", code: 0x27))
    for function in 1...12 {
        list.append((title: "F\(function)", code: UInt32(0x39 + function)))
    }
    list += [
        (title: "Enter", code: 0x28), (title: "Esc", code: 0x29), (title: "Apagar ⌫", code: 0x2A), (title: "Tab", code: 0x2B),
        (title: "Espaço", code: 0x2C), (title: "Delete ⌦", code: 0x4C), (title: "Home", code: 0x4A), (title: "End", code: 0x4D),
        (title: "Page Up", code: 0x4B), (title: "Page Down", code: 0x4E),
        (title: "→", code: 0x4F), (title: "←", code: 0x50), (title: "↓", code: 0x51), (title: "↑", code: 0x52),
    ]
    return list
}()

final class ButtonsWindowController: NSWindowController {
    private unowned let mouse: AppDelegate
    private var slots = factorySlots
    private var functionPopups: [NSPopUpButton] = []
    private var modifierChecks: [[NSButton]] = []
    private var keyPopups: [NSPopUpButton] = []
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var savedFile: URL {
        mouse.backupFolder.appendingPathComponent("botoes.json")
    }

    init(mouse: AppDelegate) {
        self.mouse = mouse
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Botões do mouse"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        var rows: [[NSView]] = []
        for name in buttonNames {
            let functionPopup = NSPopUpButton()
            functionPopup.addItems(withTitles: functions.map { $0.title } + ["Atalho de teclado"])
            functionPopup.target = self
            functionPopup.action = #selector(updateShortcutControls)
            let checks = modifiers.map { NSButton(checkboxWithTitle: $0.title, target: nil, action: nil) }
            let keyPopup = NSPopUpButton()
            keyPopup.addItems(withTitles: keys.map { $0.title })
            functionPopups.append(functionPopup)
            modifierChecks.append(checks)
            keyPopups.append(keyPopup)
            var shortcutControls: [NSView] = checks
            shortcutControls.append(keyPopup)
            rows.append([NSTextField(labelWithString: name), functionPopup, NSStackView(views: shortcutControls)])
        }
        let grid = NSGridView(views: rows)
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 10
        grid.columnSpacing = 12

        let applyButton = NSButton(title: "Gravar no mouse", target: self, action: #selector(apply))
        applyButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [
            NSButton(title: "Padrão de fábrica", target: self, action: #selector(loadFactory)),
            applyButton,
        ])
        statusLabel.preferredMaxLayoutWidth = 640

        let content = NSStackView(views: [grid, statusLabel, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.center()

        if let data = try? Data(contentsOf: savedFile), let saved = try? JSONDecoder().decode([UInt32].self, from: data), saved.count == buttonSlots {
            show(saved)
            statusLabel.stringValue = "O mouse não deixa ler os botões. Esta é a última configuração gravada por este app."
        } else {
            show(factorySlots)
            statusLabel.stringValue = "O mouse não deixa ler os botões. Este é o padrão de fábrica, que é o que o mouse tem se nunca foi alterado."
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) não é usado")
    }

    private func show(_ newSlots: [UInt32]) {
        slots = newSlots
        for (index, popup) in functionPopups.enumerated() {
            let slot = newSlots[index]
            if let function = functions.firstIndex(where: { $0.code == slot }) {
                popup.selectItem(at: function)
            } else if slot & 0xFF == shortcutType {
                popup.selectItem(at: functions.count)
                for (check, modifier) in zip(modifierChecks[index], modifiers) {
                    check.state = (slot >> 8) & modifier.bit != 0 ? .on : .off
                }
                keyPopups[index].selectItem(at: keys.firstIndex { $0.code == (slot >> 16) & 0xFF } ?? -1)
            } else {
                // Código que a janela não conhece: fica sem seleção e, ao gravar, o valor atual é mantido.
                popup.selectItem(at: -1)
            }
        }
        updateShortcutControls()
    }

    @objc private func updateShortcutControls() {
        for (index, popup) in functionPopups.enumerated() {
            let isShortcut = popup.indexOfSelectedItem == functions.count
            modifierChecks[index].forEach { $0.isEnabled = isShortcut }
            keyPopups[index].isEnabled = isShortcut
        }
    }

    @objc private func loadFactory() {
        show(factorySlots)
        statusLabel.stringValue = "Padrão de fábrica carregado na janela. Clique em \"Gravar no mouse\" para aplicar."
    }

    @objc private func apply() {
        var updated = slots
        for (index, popup) in functionPopups.enumerated() {
            let choice = popup.indexOfSelectedItem
            if choice >= 0 && choice < functions.count {
                updated[index] = functions[choice].code
            } else if choice == functions.count {
                let key = keyPopups[index].indexOfSelectedItem
                guard key >= 0 else {
                    statusLabel.stringValue = "Escolha a tecla do atalho de \"\(buttonNames[index])\"."
                    return
                }
                let mods = zip(modifierChecks[index], modifiers).reduce(UInt32(0)) { $0 | ($1.0.state == .on ? $1.1.bit : 0) }
                updated[index] = shortcutType | mods << 8 | keys[key].code << 16
            }
        }
        // Sem clique esquerdo o mouse fica inutilizável; o software oficial também recusa (tc_msg1 do text.xml).
        guard updated.prefix(buttonNames.count).contains(leftClick) else {
            statusLabel.stringValue = "Pelo menos um botão precisa ficar com \"Clique esquerdo\". Nada foi gravado."
            return
        }
        if let error = mouse.writeButtons(updated) {
            statusLabel.stringValue = error
            return
        }
        slots = updated
        do {
            try FileManager.default.createDirectory(at: mouse.backupFolder, withIntermediateDirectories: true)
            try JSONEncoder().encode(updated).write(to: savedFile)
            statusLabel.stringValue = "Gravado. O mouse não deixa ler os botões de volta: teste cada um."
        } catch {
            statusLabel.stringValue = "Gravado no mouse, mas não consegui guardar a configuração no Mac (\(error.localizedDescription))."
        }
    }
}
