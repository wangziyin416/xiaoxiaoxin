import AppKit
import Carbon
import CoreFoundation
import WebKit

private let compactSize = NSSize(width: 120, height: 56)
private let expandedSize = NSSize(width: 200, height: 200)

final class PetWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DragHandleView: NSView {
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.labelColor.withAlphaComponent(0.32).setFill()
        for row in 0..<2 {
            for column in 0..<3 {
                NSBezierPath(ovalIn: NSRect(x: CGFloat(6 + column * 5), y: CGFloat(7 + row * 5), width: 2.4, height: 2.4)).fill()
            }
        }
    }
}

@MainActor
final class DesktopBridge: NSObject, WKScriptMessageHandler {
    weak var controller: PetWindowController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let command = message.body as? String {
            switch command {
            case "collapse": controller?.setCompact(true)
            case "expand": controller?.setCompact(false)
            case "boss": controller?.toggleVisibility()
            default: break
            }
        } else if let payload = message.body as? [String: Any],
                  payload["type"] as? String == "quote",
                  let code = payload["code"] as? String {
            controller?.loadQuote(code: code)
        } else if let payload = message.body as? [String: Any],
                  payload["type"] as? String == "search",
                  let query = payload["query"] as? String {
            controller?.searchStocks(query: query)
        }
    }
}

private struct QuoteResponse: Decodable { let data: QuoteData? }
private struct QuoteData: Decodable {
    let f43: Int?
    let f44: Int?
    let f45: Int?
    let f46: Int?
    let f58: String?
    let f60: Int?
}
private struct MarketQuote {
    let name: String
    let price: Double
    let open: Double
    let high: Double
    let low: Double
    let previousClose: Double
}
private struct TrendResponse: Decodable { let data: TrendData? }
private struct TrendData: Decodable {
    let name: String?
    let decimal: Int?
    let trends: [String]?
}
private struct SearchResponse: Decodable {
    let QuotationCodeTable: SearchTable?
}
private struct SearchTable: Decodable { let Data: [SearchItem]? }
private struct SearchItem: Decodable {
    let Code: String
    let Name: String
    let QuoteID: String?
    let SecurityTypeName: String?
}

@MainActor
final class PetWindowController: NSWindowController {
    private let bridge = DesktopBridge()
    private var webView: WKWebView?
    private var compact = true
    private var savedOrigin = NSPoint.zero
    private var quoteTask: Task<Void, Never>?
    private var trendCache: [String: (date: Date, data: TrendData)] = [:]

    init() {
        let window = PetWindow(
            contentRect: NSRect(origin: .zero, size: compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        bridge.controller = self
        let content = WKUserContentController()
        content.add(bridge, name: "desktop")
        let config = WKWebViewConfiguration()
        config.userContentController = content
        let webView = WKWebView(frame: window.contentView?.bounds ?? .zero, configuration: config)
        self.webView = webView
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        window.contentView = webView

        let dragHandle = DragHandleView(frame: NSRect(x: 2, y: window.frame.height - 25, width: 25, height: 23))
        dragHandle.autoresizingMask = [.minYMargin]
        webView.addSubview(dragHandle, positioned: .above, relativeTo: nil)

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.center()

        guard let resourceRoot = Bundle.main.resourceURL else {
            fatalError("Application resources are missing")
        }
        let webRoot = resourceRoot.appendingPathComponent("Web", isDirectory: true)
        let page = webRoot.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: page.path) else {
            fatalError("Web resources are missing")
        }
        webView.loadFileURL(page, allowingReadAccessTo: webRoot)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCompact(_ shouldCompact: Bool) {
        guard compact != shouldCompact, let window else { return }
        compact = shouldCompact
        let oldFrame = window.frame
        let size = shouldCompact ? compactSize : expandedSize
        let newOrigin = NSPoint(x: oldFrame.minX, y: oldFrame.maxY - size.height)
        window.setFrame(NSRect(origin: newOrigin, size: size), display: true, animate: true)
    }

    func toggleVisibility() {
        guard let window else { return }
        if window.isVisible {
            savedOrigin = window.frame.origin
            window.orderOut(nil)
        } else {
            if savedOrigin != .zero { window.setFrameOrigin(savedOrigin) }
            window.orderFrontRegardless()
        }
    }

    func loadQuote(code: String) {
        let cleanCode = String(code.filter(\.isNumber).prefix(6))
        guard cleanCode.count == 6 else {
            sendError("请输入六位股票代码～")
            return
        }
        let market = cleanCode.hasPrefix("6") ? "1" : "0"
        let secid = "\(market).\(cleanCode)"
        quoteTask?.cancel()
        quoteTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (quote, source) = try await Self.fetchQuoteWithFallback(secid: secid, code: cleanCode)
                try Task.checkCancellation()
                let trend: TrendData
                if let cached = trendCache[cleanCode], Date().timeIntervalSince(cached.date) < 300 {
                    trend = cached.data
                } else if let freshTrend = try? await Self.fetchTrends(secid: secid) {
                    trendCache[cleanCode] = (Date(), freshTrend)
                    trend = freshTrend
                } else {
                    trend = TrendData(name: nil, decimal: 2, trends: nil)
                }
                try Task.checkCancellation()
                sendMarketData(code: cleanCode, market: market, quote: quote, trend: trend, source: source)
            } catch is CancellationError {
                return
            } catch {
                sendError("主数据源和备用源都没有回应，请稍后重试。")
            }
        }
    }

    func searchStocks(query: String) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return }
        Task { [weak self] in
            do {
                var components = URLComponents(string: "https://searchapi.eastmoney.com/api/suggest/get")!
                components.queryItems = [
                    URLQueryItem(name: "input", value: cleanQuery),
                    URLQueryItem(name: "type", value: "14"),
                    URLQueryItem(name: "token", value: "D43BF722C8E33BDC906FB84D85E326E8")
                ]
                let (data, response) = try await Self.fetchData(from: components.url!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let items = try JSONDecoder().decode(SearchResponse.self, from: data).QuotationCodeTable?.Data ?? []
                self?.sendSearchResults(Array(items.prefix(6)))
            } catch {
                self?.sendSearchResults([])
            }
        }
    }

    private static func fetchQuoteWithFallback(secid: String, code: String) async throws -> (MarketQuote, String) {
        do {
            let quote = try await fetchEastmoneyQuote(secid: secid)
            func price(_ raw: Int?) -> Double { Double(raw ?? 0) / 100.0 }
            let result = MarketQuote(
                name: quote.f58 ?? code,
                price: price(quote.f43),
                open: price(quote.f46),
                high: price(quote.f44),
                low: price(quote.f45),
                previousClose: price(quote.f60)
            )
            guard result.price > 0 else { throw URLError(.cannotParseResponse) }
            return (result, "东财")
        } catch {
            let quote = try await fetchTencentQuote(code: code)
            return (quote, "腾讯备用源")
        }
    }

    private static func fetchEastmoneyQuote(secid: String) async throws -> QuoteData {
        let fields = "f43,f44,f45,f46,f58,f60"
        let url = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=\(fields)")!
        let (data, response) = try await fetchData(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let quote = try JSONDecoder().decode(QuoteResponse.self, from: data).data else {
            throw URLError(.badServerResponse)
        }
        return quote
    }

    private static func fetchTencentQuote(code: String) async throws -> MarketQuote {
        let symbol = "\(code.hasPrefix("6") ? "sh" : "sz")\(code)"
        let url = URL(string: "https://qt.gtimg.cn/q=\(symbol)")!
        let (data, response) = try await fetchData(from: url, referer: "https://gu.qq.com/")
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let body = String(data: data, encoding: gb18030),
              let firstQuote = body.firstIndex(of: "\""),
              let lastQuote = body.lastIndex(of: "\"") else { throw URLError(.cannotDecodeContentData) }
        let values = body[body.index(after: firstQuote)..<lastQuote].split(separator: "~", omittingEmptySubsequences: false)
        guard values.count > 34,
              let current = Double(values[3]),
              let previousClose = Double(values[4]),
              let open = Double(values[5]),
              let high = Double(values[33]),
              let low = Double(values[34]), current > 0 else { throw URLError(.cannotParseResponse) }
        return MarketQuote(name: String(values[1]), price: current, open: open, high: high, low: low, previousClose: previousClose)
    }

    private static func fetchTrends(secid: String) async throws -> TrendData {
        let urlString = "https://push2his.eastmoney.com/api/qt/stock/trends2/get?secid=\(secid)&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11&fields2=f51,f52,f53,f54,f55,f56,f57,f58&ndays=1&iscr=0"
        let (data, response) = try await fetchData(from: URL(string: urlString)!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let trends = try JSONDecoder().decode(TrendResponse.self, from: data).data else {
            throw URLError(.badServerResponse)
        }
        return trends
    }

    private static func fetchData(from url: URL, referer: String = "https://quote.eastmoney.com/") async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        var lastError: Error = URLError(.unknown)
        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                if attempt > 0 {
                    let delay = attempt == 1 ? 1_000_000_000 : 3_000_000_000
                    try await Task.sleep(nanoseconds: UInt64(delay))
                }
                return try await URLSession.shared.data(for: request)
            }
            catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }

    private func sendMarketData(code: String, market: String, quote: MarketQuote, trend: TrendData, source: String) {
        let points = (trend.trends ?? []).compactMap { row -> Double? in
            let values = row.split(separator: ",")
            guard values.count > 2 else { return nil }
            return Double(values[2])
        }
        let payload: [String: Any] = [
            "name": quote.name,
            "displayCode": "\(code).\(market == "1" ? "SH" : "SZ")",
            "price": quote.price,
            "open": quote.open,
            "high": quote.high,
            "low": quote.low,
            "previousClose": quote.previousClose,
            "points": points,
            "source": source
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.applyMarketData(\(json))")
        NSLog("Market data loaded for %@ via %@ (%ld points)", code, source, points.count)
    }

    private func sendError(_ message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["message": message]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.applyMarketError(\(json).message)")
        NSLog("Market data error: %@", message)
    }

    private func sendSearchResults(_ items: [SearchItem]) {
        let payload: [[String: String]] = items.map { item in
            let suffix = item.Code.hasPrefix("6") ? "SH" : "SZ"
            return ["code": item.Code, "name": item.Name, "displayCode": "\(item.Code).\(suffix)"]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.applySearchResults(\(json))")
    }
}

private var hotKeyHandler: EventHandlerRef?
private var hotKeyRef: EventHotKeyRef?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var petController: PetWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = PetWindowController()
        petController = controller
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        installBossKey(for: controller)
        installStatusMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "信"
        item.button?.toolTip = "小小信"
        let menu = NSMenu()
        let visibility = NSMenuItem(title: "显示 / 隐藏", action: #selector(toggleFromMenu), keyEquivalent: "")
        visibility.target = self
        menu.addItem(visibility)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出小小信", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleFromMenu() { petController?.toggleVisibility() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func installBossKey(for controller: PetWindowController) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<PetWindowController>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { controller.toggleVisibility() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, Unmanaged.passUnretained(controller).toOpaque(), &hotKeyHandler)
        let hotKeyID = EventHotKeyID(signature: OSType(0x58585848), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
