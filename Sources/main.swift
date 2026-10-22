//  Archive Player — a small Cocoa shell around the single-page player.
//
//  Why a web server and not a file:// load: youtube (and a few others) refuse
//  to run their embedded player on a page with no real origin, which is what a
//  file:// page has. The app therefore serves the page to itself over the
//  loopback interface on a fixed port, so the embeds behave exactly as they do
//  on a hosted copy — and so the browser's stored pins, history and key keep
//  the same address from one launch to the next.

import AppKit
import WebKit
import Network
import Foundation

// MARK: - the marks

struct Mark {
    let name: String
    let rows: [String]
}

let MARKS: [Mark] = [
    Mark(name: "chevrons", rows: ["#...#...#..", ".#...#...#.", "..#...#...#", ".#...#...#.", "#...#...#.."]),
    Mark(name: "levels", rows: ["....#......", "..#.#...#..", "#.#.#.#.#.#", "#.#.#.#.#.#", "#.#.#.#.#.#"]),
    Mark(name: "reels", rows: [".###...###.", "#...#.#...#", "#.#.#.#.#.#", "#...#.#...#", ".###...###."]),
    Mark(name: "film", rows: ["#.#.#.#.#.#", "###########", "#.........#", "###########", "#.#.#.#.#.#"]),
    Mark(name: "framed", rows: ["##.......##", "#...#.....#", "#...##....#", "#...#.....#", "##.......##"]),
    Mark(name: "tower", rows: [".....#.....", "...#.#.#...", "..#..#..#..", ".....#.....", "...#####..."]),
    Mark(name: "disc", rows: ["...#####...", "..#.....#..", ".#...#...#.", "..#.....#..", "...#####..."]),
    Mark(name: "stack", rows: ["###########", "#.#.#.#.#.#", "###########", "#.#.#.#.#.#", "###########"]),
    Mark(name: "signal", rows: [".........#.", "......#..#.", "...#..#..#.", "#..#..#..#.", "#..#..#..#."]),
    Mark(name: "prompt", rows: ["#..........", ".#.........", "..#.####.##", ".#.........", "#.........."]),
    Mark(name: "phones", rows: ["...#####...", "..#.....#..", ".##.....##.", ".##.....##.", ".##.....##."]),
    Mark(name: "screen", rows: ["###########", "#.........#", "#.........#", "###########", "....###...."]),
    Mark(name: "book", rows: ["####.#.####", "#...#.#...#", "#...#.#...#", "#...#.#...#", "####.#.####"]),
    Mark(name: "meter", rows: [".#########.", "#....#....#", "#...#.....#", "#..#......#", ".#########."]),
    Mark(name: "dots", rows: [".#.#.#.#.#.", "...........", "#.#.#.#.#.#", "...........", ".#.#.#.#.#."]),
    Mark(name: "prism", rows: [".....#.....", "....#.#....", "...#...#...", "..#.....#..", ".#########."]),
    Mark(name: "speaker", rows: ["..##...#...", ".###..#.#..", "####..#.#.#", ".###..#.#..", "..##...#..."]),
    Mark(name: "barcode", rows: ["#.##.#.###.", "#.##.#.###.", "#.##.#.###.", "#.##.#.###.", "#.##.#.###."]),
    Mark(name: "lens", rows: [".####......", "#....#.....", "#....#.....", ".####.#....", ".......###."]),
    Mark(name: "pair", rows: ["#......#.#.", "##.....#.#.", "###....#.#.", "##.....#.#.", "#......#.#."]),
]

let TURN: TimeInterval = 600          // ten minutes, the same turn the page uses
let PORTS: [UInt16] = [8787, 8788, 8789, 8790, 8791, 8792, 8793, 8794, 8795, 8796]

func markIndexNow() -> Int {
    let slot = floor(Date().timeIntervalSince1970 / TURN)
    return Int(slot.truncatingRemainder(dividingBy: Double(MARKS.count)))
}

// the menu bar wants a template image: black art, the system does the tinting
func barImage(_ mark: Mark) -> NSImage {
    let cols = CGFloat(mark.rows[0].count), rowCount = CGFloat(mark.rows.count)
    let px: CGFloat = 2
    let size = NSSize(width: px * cols, height: px * rowCount)
    let img = NSImage(size: size, flipped: false) { _ in
        NSColor.black.setFill()
        for (y, line) in mark.rows.enumerated() {
            for (x, ch) in line.enumerated() where ch == "#" {
                NSRect(x: CGFloat(x) * px,
                       y: (rowCount - 1 - CGFloat(y)) * px,
                       width: px, height: px).fill()
            }
        }
        return true
    }
    img.isTemplate = true
    return img
}

// the dock tile: the mark on the same dark plate as the app icon, and able to
// hold two marks at once so one can fade into the next
func dockImage(from: Mark, to: Mark, t: CGFloat) -> NSImage {
    let side: CGFloat = 512
    return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        let pad = side * 0.09
        let plate = NSBezierPath(roundedRect: rect.insetBy(dx: pad, dy: pad),
                                 xRadius: side * 0.22, yRadius: side * 0.22)
        NSColor(calibratedWhite: 0.043, alpha: 1).setFill()
        plate.fill()

        func paint(_ mark: Mark, alpha: CGFloat) {
            if alpha <= 0.001 { return }
            let cols = CGFloat(mark.rows[0].count), rowCount = CGFloat(mark.rows.count)
            let px = floor((side - 2 * pad) * 0.62 / cols)
            let w = px * cols, h = px * rowCount
            let ox = (side - w) / 2, oy = (side - h) / 2
            NSColor.white.withAlphaComponent(alpha).setFill()
            for (y, line) in mark.rows.enumerated() {
                for (x, ch) in line.enumerated() where ch == "#" {
                    NSRect(x: ox + CGFloat(x) * px,
                           y: oy + (rowCount - 1 - CGFloat(y)) * px,
                           width: px, height: px).fill()
                }
            }
        }
        paint(from, alpha: 1 - t)
        paint(to, alpha: t)
        return true
    }
}

// MARK: - the loopback server

final class LocalServer {
    private var listener: NWListener?
    private let html: Data
    private(set) var port: UInt16 = 0

    init(html: Data) { self.html = html }

    private func params() -> NWParameters {
        let p = NWParameters.tcp
        p.allowLocalEndpointReuse = true
        // loopback only: nothing on the network can reach this
        p.requiredInterfaceType = .loopback
        return p
    }

    func start(ports: [UInt16], done: @escaping (UInt16?) -> Void) {
        guard let candidate = ports.first else { done(nil); return }
        let rest = Array(ports.dropFirst())
        guard let nwPort = NWEndpoint.Port(rawValue: candidate),
              let l = try? NWListener(using: params(), on: nwPort) else {
            start(ports: rest, done: done)
            return
        }
        var settled = false
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            guard let self = self, !settled else { return }
            switch state {
            case .ready:
                settled = true
                self.listener = l
                self.port = candidate
                done(candidate)
            case .failed, .cancelled:
                settled = true
                l.cancel()
                self.start(ports: rest, done: done)
            default:
                break
            }
        }
        l.start(queue: .main)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        read(c, buffer: Data())
    }

    private func read(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self = self else { c.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if error != nil || buf.count > 128 * 1024 { c.cancel(); return }
            if let text = String(data: buf, encoding: .utf8), text.contains("\r\n\r\n") {
                self.respond(c, request: text)
                return
            }
            if isComplete { c.cancel(); return }
            self.read(c, buffer: buf)
        }
    }

    private func respond(_ c: NWConnection, request: String) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let bits = firstLine.split(separator: " ")
        let path = bits.count > 1 ? String(bits[1]) : "/"
        let wantsPage = path == "/" || path == "/index.html" || path.hasPrefix("/?")

        var body = html
        var status = "200 OK"
        var type = "text/html; charset=utf-8"
        if !wantsPage {
            body = Data("not here".utf8)
            status = "404 Not Found"
            type = "text/plain; charset=utf-8"
        }
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(type)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}

// MARK: - the app

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate {

    var window: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var server: LocalServer?
    var address: URL?
    var showingMark = -1
    var markTimer: Timer?
    var fadeTimer: Timer?
    var downloadTarget: URL?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()
        buildWindow()
        buildStatusItem()
        applyMark(fade: false)
        scheduleMark()

        guard let page = Bundle.main.url(forResource: "archive-video-player", withExtension: "html"),
              let data = try? Data(contentsOf: page) else {
            show(message: "The player page is missing from the app bundle.")
            return
        }
        let s = LocalServer(html: data)
        server = s
        s.start(ports: PORTS) { [weak self] port in
            guard let self = self else { return }
            guard let port = port, let url = URL(string: "http://127.0.0.1:\(port)/") else {
                self.show(message: "Couldn't open a local port for the player.")
                return
            }
            self.address = url
            self.web.load(URLRequest(url: url))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: window

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()      // pins, history and the key persist

        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1180, height: 820), configuration: config)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false

        window = NSWindow(contentRect: web.frame,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Archive Player"
        window.backgroundColor = NSColor.black
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.setFrameAutosaveName("ArchivePlayerWindow")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func show(message: String) {
        let alert = NSAlert()
        alert.messageText = "Archive Player"
        alert.informativeText = message
        alert.runModal()
    }

    // MARK: the marks, in the dock and the bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("Show Player", #selector(showWindow)),
            ("Reload", #selector(reload)),
            ("Open in Browser", #selector(openInBrowser)),
            ("Copy Address", #selector(copyAddress))
        ]
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Archive Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func applyMark(fade: Bool) {
        let next = markIndexNow()
        if next == showingMark { return }
        let previous = showingMark >= 0 ? MARKS[showingMark] : MARKS[next]
        let mark = MARKS[next]
        showingMark = next

        statusItem?.button?.toolTip = "archive player — \(mark.name)"

        guard fade else {
            NSApp.applicationIconImage = dockImage(from: mark, to: mark, t: 1)
            statusItem?.button?.image = barImage(mark)
            return
        }
        fadeTimer?.invalidate()
        var step = 0
        let steps = 14
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { [weak self] t in
            step += 1
            let f = CGFloat(step) / CGFloat(steps)
            NSApp.applicationIconImage = dockImage(from: previous, to: mark, t: f)
            if step == steps / 2 { self?.statusItem?.button?.image = barImage(mark) }
            if step >= steps { t.invalidate() }
        }
    }

    private func scheduleMark() {
        markTimer?.invalidate()
        let now = Date().timeIntervalSince1970
        let wait = TURN - now.truncatingRemainder(dividingBy: TURN) + 0.2
        let t = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            self?.applyMark(fade: true)
            self?.scheduleMark()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        markTimer = t
    }

    // MARK: menu actions

    @objc func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func reload() {
        if let url = address, web.url == nil {
            web.load(URLRequest(url: url))
        } else {
            web.reload()
        }
    }

    @objc func openInBrowser() {
        if let url = address { NSWorkspace.shared.open(url) }
    }

    @objc func copyAddress() {
        guard let url = address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu(title: "Archive Player")
        appMenu.addItem(withTitle: "About Archive Player",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Archive Player", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Archive Player", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: Selector(("performClose:")), keyEquivalent: "w")
        let reloadItem = NSMenuItem(title: "Reload Page", action: #selector(reload), keyEquivalent: "r")
        reloadItem.target = self
        fileMenu.addItem(reloadItem)
        let openItem = NSMenuItem(title: "Open in Browser", action: #selector(openInBrowser), keyEquivalent: "b")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileItem.submenu = fileMenu

        // without this the page's own text fields can't be pasted into
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: Selector(("selectAll:")), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Enter Full Screen", action: Selector(("toggleFullScreen:")), keyEquivalent: "f")
        viewItem.submenu = viewMenu

        NSApp.mainMenu = main
    }

    // MARK: web view behaviour

    // target="_blank" links (watch on youtube, source links) go to the real browser
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if #available(macOS 11.3, *), navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        // a clicked link that would take the window off the player goes outside instead
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame ?? true,
           let url = navigationAction.request.url,
           url.host != "127.0.0.1" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    @available(macOS 11.3, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // the page asks for the microphone only if you use transcribe
    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }
}

// MARK: - saving a transcript

@available(macOS 11.3, *)
extension AppDelegate: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let fm = FileManager.default
        let dir = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.homeDirectoryForCurrentUser
        let name = suggestedFilename.isEmpty ? "transcript.txt" : suggestedFilename
        let first = dir.appendingPathComponent(name)
        let base = first.deletingPathExtension().lastPathComponent
        let ext = first.pathExtension.isEmpty ? "txt" : first.pathExtension
        var target = first
        var n = 1
        while fm.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        downloadTarget = target
        completionHandler(target)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadTarget else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        NSSound.beep()
    }
}

// MARK: - go

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
