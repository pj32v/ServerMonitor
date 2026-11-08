import SwiftUI
import AppKit
import Foundation
import Darwin
import Combine

// MARK: - Direct Keystroke Interactive NSTextView (MobaXterm Style)
class TerminalTextView: NSTextView {
    var onKeyData: ((Data) -> Void)?
    var onUserInteraction: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Page Up & Page Down for scrolling terminal history without jumping
        if event.keyCode == 116 { // Page Up
            pageUp(nil)
            return
        }
        if event.keyCode == 121 { // Page Down
            pageDown(nil)
            return
        }

        onUserInteraction?()

        // Control + Key combinations (e.g. Ctrl+C = 0x03, Ctrl+D = 0x04, Ctrl+L = 0x0C)
        if event.modifierFlags.contains(.control) {
            if let chars = event.charactersIgnoringModifiers, let first = chars.utf16.first {
                if first >= 97 && first <= 122 { // a-z
                    let code = UInt8(first - 96)
                    onKeyData?(Data([code]))
                    return
                } else if first >= 65 && first <= 90 { // A-Z
                    let code = UInt8(first - 64)
                    onKeyData?(Data([code]))
                    return
                }
            }
        }

        // Command + V (Paste clipboard into terminal)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v" {
            if let clipboard = NSPasteboard.general.string(forType: .string),
               let data = clipboard.data(using: .utf8) {
                onKeyData?(data)
                return
            }
        }

        // Command + C (Copy selected text)
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "c" {
            super.keyDown(with: event)
            return
        }

        // Standard terminal keys
        switch event.keyCode {
        case 36: // Enter (Carriage return)
            onKeyData?(Data([0x0D]))
        case 51: // Backspace (ASCII DEL 0x7F)
            onKeyData?(Data([0x7F]))
        case 48: // Tab (0x09)
            onKeyData?(Data([0x09]))
        case 53: // Escape (0x1B)
            onKeyData?(Data([0x1B]))
        case 126: // Up Arrow (\e[A)
            onKeyData?(Data([0x1B, 0x5B, 0x41]))
        case 125: // Down Arrow (\e[B)
            onKeyData?(Data([0x1B, 0x5B, 0x42]))
        case 124: // Right Arrow (\e[C)
            onKeyData?(Data([0x1B, 0x5B, 0x43]))
        case 123: // Left Arrow (\e[D)
            onKeyData?(Data([0x1B, 0x5B, 0x44]))
        default:
            if let chars = event.characters, let data = chars.data(using: .utf8) {
                onKeyData?(data)
            }
        }
    }
}

// MARK: - Terminal Display Buffer with ANSI Color & Stream Processing
class TerminalDisplayBuffer {
    var rawText = NSMutableAttributedString()
    var currentForeground: NSColor = NSColor(white: 0.92, alpha: 1.0)
    var isBold: Bool = false

    private var pendingRun: String = ""

    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)

    let colorMap: [Int: NSColor] = [
        0: NSColor(white: 0.92, alpha: 1.0),
        30: NSColor.black,
        31: NSColor(red: 0.97, green: 0.44, blue: 0.44, alpha: 1.0), // Red
        32: NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0), // Emerald Green
        33: NSColor(red: 0.98, green: 0.75, blue: 0.14, alpha: 1.0), // Amber / Yellow
        34: NSColor(red: 0.38, green: 0.65, blue: 0.98, alpha: 1.0), // Blue
        35: NSColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0), // Magenta
        36: NSColor(red: 0.13, green: 0.83, blue: 0.93, alpha: 1.0), // Cyan
        37: NSColor(white: 0.95, alpha: 1.0),                         // White
        90: NSColor(white: 0.60, alpha: 1.0),                         // Gray
        91: NSColor(red: 1.0, green: 0.55, blue: 0.55, alpha: 1.0),
        92: NSColor(red: 0.35, green: 0.95, blue: 0.70, alpha: 1.0),
        93: NSColor(red: 1.0, green: 0.85, blue: 0.30, alpha: 1.0),
        94: NSColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0),
        95: NSColor(red: 0.85, green: 0.65, blue: 1.0, alpha: 1.0),
        96: NSColor(red: 0.35, green: 0.95, blue: 1.0, alpha: 1.0),
        97: NSColor.white
    ]

    private var isInsideOSC: Bool = false

    private func flushPendingRun() {
        guard !pendingRun.isEmpty else { return }
        let attr: [NSAttributedString.Key: Any] = [
            .foregroundColor: currentForeground,
            .font: isBold ? boldFont : font
        ]
        rawText.append(NSAttributedString(string: pendingRun, attributes: attr))
        pendingRun.removeAll(keepingCapacity: true)
    }

    func processIncoming(_ string: String) {
        let str = string.replacingOccurrences(of: "\r\n", with: "\n")
        var i = str.startIndex

        while i < str.endIndex {
            let c = str[i]

            // 1. If currently inside an OSC sequence (e.g. \e]133;... or \e]0;...), swallow until \a (0x07) or \e\
            if isInsideOSC {
                if c == "\u{0007}" { // BEL
                    isInsideOSC = false
                    i = str.index(after: i)
                    continue
                } else if c == "\u{001B}" {
                    let next = str.index(after: i)
                    if next < str.endIndex && str[next] == "\\" { // ST
                        isInsideOSC = false
                        i = str.index(after: next)
                        continue
                    }
                }
                i = str.index(after: i)
                continue
            }

            // 2. Ignore lone BEL
            if c == "\u{0007}" {
                i = str.index(after: i)
                continue
            }

            // 3. Backspace
            if c == "\u{0008}" {
                let next = str.index(after: i)
                if next < str.endIndex && str[next] == " " {
                    let next2 = str.index(after: next)
                    if next2 < str.endIndex && str[next2] == "\u{0008}" {
                        deleteLastChar()
                        i = str.index(after: next2)
                        continue
                    }
                }
                deleteLastChar()
                i = next
                continue
            }

            // 4. Carriage Return
            if c == "\r" {
                i = str.index(after: i)
                continue
            }

            // 5. Escape Sequences
            if c == "\u{001B}" {
                let afterEsc = str.index(after: i)
                guard afterEsc < str.endIndex else {
                    break
                }
                let nextChar = str[afterEsc]

                // OSC (Operating System Command): \e] ... (\a or \e\)
                if nextChar == "]" {
                    flushPendingRun()
                    isInsideOSC = true
                    i = str.index(after: afterEsc)
                    continue
                }

                // CSI (Control Sequence Introducer): \e[ ... [@-~]
                if nextChar == "[" {
                    var csiEnd = str.index(after: afterEsc)
                    var found = false
                    while csiEnd < str.endIndex {
                        let ch = str[csiEnd]
                        if (ch >= "@" && ch <= "~") {
                            flushPendingRun()
                            let seq = String(str[i...csiEnd])
                            handleCSI(seq)
                            i = str.index(after: csiEnd)
                            found = true
                            break
                        }
                        csiEnd = str.index(after: csiEnd)
                    }
                    if !found {
                        i = str.endIndex
                    }
                    continue
                }

                // Character sets: \e(B, \e)0, etc.
                if nextChar == "(" || nextChar == ")" || nextChar == "*" || nextChar == "+" {
                    let third = str.index(after: afterEsc)
                    if third < str.endIndex {
                        i = str.index(after: third)
                    } else {
                        i = str.endIndex
                    }
                    continue
                }

                // 2-character escape codes: \e=, \e>, \e7, \e8, etc.
                i = str.index(after: afterEsc)
                continue
            }

            // 6. Normal character or newline - batch into pendingRun
            pendingRun.append(c)
            i = str.index(after: i)
        }

        // Flush any remaining characters in the run
        flushPendingRun()

        // Limit memory buffer size to ~150k characters
        if rawText.length > 150_000 {
            rawText.deleteCharacters(in: NSRange(location: 0, length: 50_000))
        }
    }

    private func deleteLastChar() {
        if !pendingRun.isEmpty {
            pendingRun.removeLast()
        } else if rawText.length > 0 {
            rawText.deleteCharacters(in: NSRange(location: rawText.length - 1, length: 1))
        }
    }

    private func handleCSI(_ seq: String) {
        if seq == "\u{001B}[2J" || seq == "\u{001B}[H" || seq == "\u{001B}[H\u{001B}[2J" {
            pendingRun.removeAll()
            rawText = NSMutableAttributedString()
        } else if seq.hasSuffix("m") {
            let inner = String(seq.dropFirst(2).dropLast())
            let codes = inner.split(separator: ";").compactMap { Int($0) }
            if codes.isEmpty || codes.contains(0) {
                currentForeground = NSColor(white: 0.92, alpha: 1.0)
                isBold = false
            }
            for code in codes {
                if code == 1 { isBold = true }
                if let color = colorMap[code] {
                    currentForeground = color
                }
            }
        }
    }

    func getRenderedText(showCursor: Bool) -> NSAttributedString {
        flushPendingRun()
        let copy = NSMutableAttributedString(attributedString: rawText)
        if showCursor {
            let cursorAttr: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1.0),
                .font: boldFont
            ]
            copy.append(NSAttributedString(string: "█", attributes: cursorAttr))
        }
        return copy
    }

    func clear() {
        pendingRun.removeAll()
        rawText = NSMutableAttributedString()
    }
}

// MARK: - In-App Live Interactive SSH Terminal Session (PTY)
@MainActor
class SSHTerminalSession: ObservableObject {
    @Published var displayAttributedString: NSAttributedString = NSAttributedString()
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var connectionError: String?
    @Published var contentVersion: Int = 0
    @Published var scrollToBottomRequested: Bool = false

    private let buffer = TerminalDisplayBuffer()
    private var masterFd: Int32 = -1
    private var slaveFd: Int32 = -1
    private var process: Process?
    private var masterHandle: FileHandle?
    private var askpassURL: URL?

    init() {}

    func connect(profile: ServerProfile) {
        guard !isConnecting && !isConnected else { return }
        isConnecting = true
        connectionError = nil

        buffer.clear()
        buffer.processIncoming("⚡ 正在连接至 \(profile.name) (\(profile.username)@\(profile.host):\(profile.port))...\n")
        contentVersion += 1
        scrollToBottomRequested = true
        displayAttributedString = buffer.getRenderedText(showCursor: true)

        let portNum = Int(profile.port) ?? 22

        do {
            guard openpty(&masterFd, &slaveFd, nil, nil, nil) == 0 else {
                throw NSError(domain: "PTY", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "无法创建虚拟终端 (openpty failed)"])
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

            var args = [
                "-tt",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", String(portNum)
            ]

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"

            if profile.authMethod == .password {
                let askpass = FileManager.default.temporaryDirectory.appendingPathComponent("askpass_\(UUID().uuidString).sh")
                let escaped = profile.password
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "$", with: "\\$")
                let scriptContent = "#!/bin/sh\necho \"\(escaped)\"\n"
                try scriptContent.write(to: askpass, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpass.path)
                self.askpassURL = askpass

                env["SSH_ASKPASS"] = askpass.path
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"] = ":0"
            } else {
                let resolvedKey = (profile.keyPath as NSString).expandingTildeInPath
                if !profile.keyPath.isEmpty && FileManager.default.fileExists(atPath: resolvedKey) {
                    args.append(contentsOf: ["-i", resolvedKey])
                }
            }

            args.append("\(profile.username)@\(profile.host)")

            proc.arguments = args
            proc.environment = env

            let slaveHandle = FileHandle(fileDescriptor: slaveFd, closeOnDealloc: false)
            proc.standardInput = slaveHandle
            proc.standardOutput = slaveHandle
            proc.standardError = slaveHandle

            try proc.run()
            close(slaveFd)
            self.slaveFd = -1
            self.process = proc

            let handle = FileHandle(fileDescriptor: masterFd, closeOnDealloc: true)
            self.masterHandle = handle

            handle.readabilityHandler = { [weak self] h in
                let data = h.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.buffer.processIncoming(str)
                        self.contentVersion += 1
                        self.displayAttributedString = self.buffer.getRenderedText(showCursor: self.isConnected)
                    }
                }
            }

            proc.terminationHandler = { [weak self] p in
                Task { @MainActor [weak self] in
                    self?.handleTermination(status: p.terminationStatus)
                }
            }

            self.isConnected = true
            self.isConnecting = false

        } catch {
            self.isConnecting = false
            self.isConnected = false
            self.connectionError = error.localizedDescription
            buffer.processIncoming("\n❌ 连接失败: \(error.localizedDescription)\n")
            contentVersion += 1
            displayAttributedString = buffer.getRenderedText(showCursor: false)
        }
    }

    func sendRawData(_ data: Data) {
        guard let handle = masterHandle else { return }
        handle.write(data)
    }

    func sendCommand(_ cmd: String) {
        if let data = (cmd + "\r").data(using: .utf8) {
            sendRawData(data)
            scrollToBottomRequested = true
        }
    }

    func sendInterrupt() {
        sendRawData(Data([0x03])) // Ctrl+C
        scrollToBottomRequested = true
    }

    func clear() {
        buffer.clear()
        contentVersion += 1
        scrollToBottomRequested = true
        displayAttributedString = buffer.getRenderedText(showCursor: true)
    }

    isolated deinit {
        disconnect()
    }

    func disconnect() {
        masterHandle?.readabilityHandler = nil
        masterHandle = nil
        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        if slaveFd >= 0 {
            close(slaveFd)
            slaveFd = -1
        }
        if let askpass = askpassURL {
            try? FileManager.default.removeItem(at: askpass)
            askpassURL = nil
        }
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        isConnected = false
        isConnecting = false
    }

    private func handleTermination(status: Int32) {
        isConnected = false
        isConnecting = false
        buffer.processIncoming("\n⚡ SSH 会话已结束 (退出代码: \(status))。\n")
        contentVersion += 1
        displayAttributedString = buffer.getRenderedText(showCursor: false)
    }
}

// MARK: - Native AppKit Terminal NSViewRepresentable
struct NativeTerminalView: NSViewRepresentable {
    @ObservedObject var session: SSHTerminalSession

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.09, alpha: 1.0)

        let textView = TerminalTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        textView.onKeyData = { [weak session] data in
            session?.sendRawData(data)
        }

        let coordinator = context.coordinator
        textView.onUserInteraction = { [weak coordinator, weak textView] in
            guard let coordinator = coordinator, let textView = textView else { return }
            coordinator.isUserScrolledUp = false
            textView.scrollToEndOfDocument(nil)
        }

        scrollView.documentView = textView
        coordinator.textView = textView
        coordinator.scrollView = scrollView

        // Click on background focuses the terminal
        let clickRecognizer = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleClick))
        scrollView.addGestureRecognizer(clickRecognizer)

        // Listen for user scrolling
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.handleBoundsChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )

        // Give initial focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Explicit command/clear scroll request
        if session.scrollToBottomRequested {
            DispatchQueue.main.async {
                session.scrollToBottomRequested = false
            }
            context.coordinator.isUserScrolledUp = false
            textView.scrollToEndOfDocument(nil)
        }

        // Only update text storage when content version has actually changed
        if context.coordinator.lastContentVersion != session.contentVersion {
            context.coordinator.lastContentVersion = session.contentVersion

            let wasAtBottom = context.coordinator.isScrolledToBottom(nsView)
            let prevVisibleOrigin = nsView.contentView.bounds.origin

            textView.textStorage?.setAttributedString(session.displayAttributedString)

            if wasAtBottom && !context.coordinator.isUserScrolledUp {
                textView.scrollToEndOfDocument(nil)
            } else {
                // User has scrolled up: preserve their reading position precisely!
                nsView.contentView.scroll(to: prevVisibleOrigin)
                nsView.reflectScrolledClipView(nsView.contentView)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var textView: TerminalTextView?
        weak var scrollView: NSScrollView?
        var lastContentVersion: Int = -1
        var isUserScrolledUp: Bool = false

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func handleClick() {
            textView?.window?.makeFirstResponder(textView)
        }

        func isScrolledToBottom(_ sv: NSScrollView) -> Bool {
            guard let docView = sv.documentView else { return true }
            let visibleRect = sv.documentVisibleRect
            let docHeight = docView.bounds.height
            let visibleBottom = visibleRect.origin.y + visibleRect.size.height
            return (docHeight - visibleBottom) <= 25.0
        }

        @objc func handleBoundsChange(_ notification: Notification) {
            guard let sv = scrollView, let docView = sv.documentView else { return }
            let visibleRect = sv.documentVisibleRect
            let docHeight = docView.bounds.height
            let visibleBottom = visibleRect.origin.y + visibleRect.size.height
            let distanceToBottom = docHeight - visibleBottom

            if distanceToBottom > 35.0 {
                isUserScrolledUp = true
            } else if distanceToBottom <= 10.0 {
                isUserScrolledUp = false
            }
        }
    }
}

// MARK: - MobaXterm-Style Direct In-App SSH Terminal Sheet
struct SSHTerminalSheet: View {
    @EnvironmentObject var viewModel: MonitorViewModel
    @Environment(\.dismiss) private var dismiss

    var terminal: SSHTerminalSession? {
        viewModel.activeTerminalSession
    }

    let quickCommands = [
        "ls -la",
        "cd /",
        "docker ps",
        "df -h",
        "free -m",
        "top -b -n 1 | head -15",
        "uptime",
        "who",
        "cat /etc/os-release"
    ]

    var body: some View {
        Group {
            if let terminal = terminal {
                VStack(spacing: 0) {
                    // Header
                    headerView(terminal: terminal)

                    Divider().opacity(0.3)

                    // Quick command chips
                    quickCommandsBar(terminal: terminal)

                    Divider().opacity(0.3)

                    // Direct MobaXterm-style Interactive Terminal View
                    NativeTerminalView(session: terminal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onAppear {
                    if !terminal.isConnected && !terminal.isConnecting, let profile = viewModel.activeSession?.profile {
                        terminal.connect(profile: profile)
                    }
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在准备终端会话...")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                    Button("关闭") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .background(Color(red: 0.05, green: 0.06, blue: 0.09))
    }

    // MARK: - Header
    private func headerView(terminal: SSHTerminalSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.electricBlue.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: "terminal.fill")
                    .foregroundColor(.electricBlue)
                    .font(.system(size: 15))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("SSH 远程终端")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)

                    Text(viewModel.activeSession?.profile.name ?? "")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .foregroundColor(.white.opacity(0.9))

                    // Live Status Pill
                    HStack(spacing: 5) {
                        Circle()
                            .fill(terminal.isConnected ? Color.emeraldGreen : (terminal.isConnecting ? Color.vibrantOrange : Color.vibrantRed))
                            .frame(width: 7, height: 7)

                        Text(terminal.isConnected ? "PTY 实时会话 (可直接在屏幕输入)" : (terminal.isConnecting ? "正在连接..." : "已断开"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(terminal.isConnected ? .emeraldGreen : .secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.3))
                    .clipShape(Capsule())
                }

                Text("\(viewModel.username)@\(viewModel.host):\(viewModel.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            // Header Toolbar Actions
            HStack(spacing: 8) {
                Button(action: { terminal.sendInterrupt() }) {
                    Label("中断 (⌃C)", systemImage: "xmark.circle")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.vibrantRed.opacity(0.15))
                        .foregroundColor(.vibrantRed)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("发送 Ctrl+C 中断当前命令")

                Button(action: { terminal.clear() }) {
                    Label("清屏", systemImage: "trash")
                        .font(.system(size: 11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white.opacity(0.8))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("清空当前终端屏幕")

                Button(action: {
                    terminal.disconnect()
                    if let profile = viewModel.activeSession?.profile {
                        terminal.connect(profile: profile)
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.white.opacity(0.8))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("重新建立 SSH PTY 终端会话")

                Divider()
                    .frame(height: 14)
                    .opacity(0.3)

                // Minimize Button
                Button(action: {
                    viewModel.minimizeTerminal()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                        Text("最小化")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.vibrantOrange.opacity(0.18))
                    .foregroundColor(.vibrantOrange)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("最小化终端并在后台保持连接，返回主界面查看参数")

                // Close Button
                Button(action: {
                    viewModel.closeTerminal()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help("断开并关闭终端")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(red: 0.10, green: 0.11, blue: 0.15))
    }

    // MARK: - Quick Commands Toolbar
    private func quickCommandsBar(terminal: SSHTerminalSession) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("快捷指令:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))

                ForEach(quickCommands, id: \.self) { cmd in
                    Button(action: {
                        terminal.sendCommand(cmd)
                    }) {
                        Text(cmd)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
        .background(Color(red: 0.08, green: 0.09, blue: 0.13))
    }
}
