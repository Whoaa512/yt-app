import Cocoa
import WebKit

class JSConsoleWindowController: NSWindowController, NSTextFieldDelegate, WKScriptMessageHandler {
    private weak var targetWebView: WKWebView?
    private let outputTextView = NSTextView()
    private let inputField = NSTextField()
    private var commandHistory: [String] = []
    private var historyIndex: Int = -1
    private var verboseEnabled = false
    private var verboseButton: NSButton?

    init(webView: WKWebView?) {
        self.targetWebView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "JS Console"
        window.minSize = NSSize(width: 400, height: 200)
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
        loadInitialInfo()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Output scroll view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true

        outputTextView.isEditable = false
        outputTextView.isSelectable = true
        outputTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        outputTextView.backgroundColor = NSColor(white: 0.1, alpha: 1)
        outputTextView.textColor = NSColor(white: 0.9, alpha: 1)
        outputTextView.isVerticallyResizable = true
        outputTextView.isHorizontallyResizable = false
        outputTextView.autoresizingMask = [.width]
        outputTextView.textContainer?.widthTracksTextView = true
        outputTextView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = outputTextView
        scrollView.backgroundColor = NSColor(white: 0.1, alpha: 1)

        // Input row
        let promptLabel = NSTextField(labelWithString: "❯")
        promptLabel.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        promptLabel.textColor = .systemGreen
        promptLabel.translatesAutoresizingMaskIntoConstraints = false

        inputField.placeholderString = "Enter JavaScript…"
        inputField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        inputField.target = self
        inputField.action = #selector(executeInput)
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.focusRingType = .none
        inputField.bezelStyle = .roundedBezel

        let inputRow = NSView()
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.addSubview(promptLabel)
        inputRow.addSubview(inputField)

        // Quick buttons
        let buttonBar = NSStackView()
        buttonBar.orientation = .horizontal
        buttonBar.spacing = 4
        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        buttonBar.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

        let shortcuts: [(String, String)] = [
            ("localStorage", "JSON.stringify(Object.fromEntries(Object.entries(localStorage).filter(([k])=>k.includes('theater')||k.includes('player'))), null, 2)"),
            ("Cookies", "document.cookie.split(';').map(c=>c.trim()).filter(c=>c.includes('wide')||c.includes('PREF')).join('\\n')"),
            ("Video State", "(function(){const v=document.querySelector('video');return v?JSON.stringify({rate:v.playbackRate,paused:v.paused,src:v.src.substring(0,80)},null,2):'No video'})()"),
            ("Theater?", "document.querySelector('ytd-watch-flexy')?.hasAttribute('theater')"),
            ("Clear", ""),
        ]

        for (title, js) in shortcuts {
            let btn = NSButton(title: title, target: self, action: #selector(quickButtonClicked(_:)))
            btn.bezelStyle = .recessed
            btn.font = .systemFont(ofSize: 10, weight: .medium)
            btn.tag = buttonBar.arrangedSubviews.count
            btn.toolTip = js.isEmpty ? "Clear console" : js
            buttonBar.addArrangedSubview(btn)
        }
        self.quickScripts = shortcuts.map { $0.1 }

        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonBar.addArrangedSubview(spacer)

        // Verbose toggle
        let vBtn = NSButton(title: "🔇 Verbose", target: self, action: #selector(toggleVerbose(_:)))
        vBtn.bezelStyle = .recessed
        vBtn.font = .systemFont(ofSize: 10, weight: .medium)
        vBtn.toolTip = "Log all YouTube events, clicks, localStorage writes, DOM mutations"
        buttonBar.addArrangedSubview(vBtn)
        self.verboseButton = vBtn

        contentView.addSubview(buttonBar)
        contentView.addSubview(scrollView)
        contentView.addSubview(inputRow)

        NSLayoutConstraint.activate([
            buttonBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            buttonBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            buttonBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            buttonBar.heightAnchor.constraint(equalToConstant: 24),

            scrollView.topAnchor.constraint(equalTo: buttonBar.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor),

            inputRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            inputRow.heightAnchor.constraint(equalToConstant: 32),

            promptLabel.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 8),
            promptLabel.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),

            inputField.leadingAnchor.constraint(equalTo: promptLabel.trailingAnchor, constant: 4),
            inputField.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -8),
            inputField.centerYAnchor.constraint(equalTo: inputRow.centerYAnchor),
        ])
    }

    private var quickScripts: [String] = []

    // MARK: - Verbose Logging

    @objc private func toggleVerbose(_ sender: NSButton) {
        verboseEnabled = !verboseEnabled
        sender.title = verboseEnabled ? "🔊 Verbose" : "🔇 Verbose"

        if verboseEnabled {
            startVerboseLogging()
            appendOutput("// Verbose logging ON — capturing events, clicks, storage, mutations", color: .systemYellow)
        } else {
            stopVerboseLogging()
            appendOutput("// Verbose logging OFF", color: .systemYellow)
        }
    }

    private func startVerboseLogging() {
        guard let wv = targetWebView else {
            appendOutput("Error: No active WebView", color: .systemRed)
            return
        }

        // Register message handler
        wv.configuration.userContentController.add(self, name: "verboseLog")

        let js = """
        (function() {
            if (window.__ytVerbose) return;
            window.__ytVerbose = true;

            function send(type, detail) {
                if (window.webkit && window.webkit.messageHandlers.verboseLog) {
                    window.webkit.messageHandlers.verboseLog.postMessage(JSON.stringify({type, detail, time: new Date().toISOString().substr(11,12)}));
                }
            }

            // 1. YouTube custom events
            const ytEvents = [
                'yt-navigate-start', 'yt-navigate-finish', 'yt-navigate-error',
                'yt-page-data-updated', 'yt-page-type-changed',
                'yt-set-theater-mode-enabled', 'yt-action',
                'yt-render-stale-state', 'yt-player-updated',
                'yt-update-title'
            ];
            ytEvents.forEach(function(name) {
                document.addEventListener(name, function(e) {
                    let info = name;
                    if (e.detail) {
                        try { info += ' ' + JSON.stringify(e.detail).substring(0, 300); } catch(x) {}
                    }
                    send('yt-event', info);
                }, true);
            });

            // 2. All custom events on document (catch-all for yt-*)
            const origDispatch = EventTarget.prototype.dispatchEvent;
            EventTarget.prototype.dispatchEvent = function(event) {
                if (event && event.type && event.type.startsWith('yt-') && !ytEvents.includes(event.type)) {
                    let info = event.type;
                    if (event.detail) {
                        try { info += ' ' + JSON.stringify(event.detail).substring(0, 200); } catch(x) {}
                    }
                    send('yt-event', info);
                }
                return origDispatch.apply(this, arguments);
            };

            // 3. Click observer — log clicks on interactive YouTube elements
            document.addEventListener('click', function(e) {
                const el = e.target.closest('button, a, [role="button"], ytd-toggle-button-renderer, tp-yt-paper-button, .ytp-button');
                if (!el) return;
                const tag = el.tagName.toLowerCase();
                const cls = el.className ? ('.' + el.className.split(' ').slice(0,3).join('.')) : '';
                const aria = el.getAttribute('aria-label') || '';
                const text = (el.textContent || '').trim().substring(0, 50);
                send('click', tag + cls + (aria ? ' [' + aria + ']' : '') + (text && !aria ? ' "' + text + '"' : ''));
            }, true);

            // 4. localStorage write interception
            const origSetItem = Storage.prototype.setItem;
            Storage.prototype.setItem = function(key, value) {
                send('localStorage.set', key + ' = ' + String(value).substring(0, 300));
                return origSetItem.apply(this, arguments);
            };
            const origRemoveItem = Storage.prototype.removeItem;
            Storage.prototype.removeItem = function(key) {
                send('localStorage.remove', key);
                return origRemoveItem.apply(this, arguments);
            };

            // 5. Cookie write interception
            const cookieDesc = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie') ||
                               Object.getOwnPropertyDescriptor(HTMLDocument.prototype, 'cookie');
            if (cookieDesc && cookieDesc.set) {
                const origSet = cookieDesc.set;
                Object.defineProperty(document, 'cookie', {
                    get: cookieDesc.get,
                    set: function(val) {
                        const name = val.split('=')[0];
                        if (['PREF', 'wide', 'VISITOR'].some(k => name.includes(k))) {
                            send('cookie.set', val.substring(0, 300));
                        }
                        return origSet.call(this, val);
                    },
                    configurable: true
                });
            }

            // 6. Attribute mutations on ytd-watch-flexy
            function watchFlexy() {
                const flexy = document.querySelector('ytd-watch-flexy');
                if (!flexy || flexy.__verboseObserved) return;
                flexy.__verboseObserved = true;
                const obs = new MutationObserver(function(muts) {
                    muts.forEach(function(m) {
                        if (m.type === 'attributes') {
                            const val = flexy.getAttribute(m.attributeName);
                            send('flexy-attr', m.attributeName + (val !== null ? '="' + String(val).substring(0,100) + '"' : ' [removed]'));
                        }
                    });
                });
                obs.observe(flexy, { attributes: true });
                send('info', 'Watching ytd-watch-flexy attributes');
            }
            watchFlexy();
            window.addEventListener('yt-navigate-finish', function() { setTimeout(watchFlexy, 500); });

            send('info', 'Verbose logging started');
        })();
        """;

        wv.evaluateJavaScript(js)
    }

    private func stopVerboseLogging() {
        targetWebView?.evaluateJavaScript("window.__ytVerbose = false;")
        targetWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "verboseLog")
    }

    // MARK: - WKScriptMessageHandler (verbose logs)

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "verboseLog",
              let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let type = json["type"] as? String ?? "?"
        let detail = json["detail"] as? String ?? ""
        let time = json["time"] as? String ?? ""

        let color: NSColor
        switch type {
        case "yt-event": color = .systemPurple
        case "click": color = .systemOrange
        case "localStorage.set", "localStorage.remove": color = .systemTeal
        case "cookie.set": color = .systemPink
        case "flexy-attr": color = .systemYellow
        case "info": color = .systemGray
        default: color = .secondaryLabelColor
        }

        DispatchQueue.main.async {
            self.appendOutput("[\(time)] \(type): \(detail)", color: color)
        }
    }

    private func loadInitialInfo() {
        appendOutput("// JS Console — connected to active tab", color: .systemGray)
        appendOutput("// Use quick buttons above or type JS below", color: .systemGray)
        appendOutput("// Safari Web Inspector also available: Develop → YTApp", color: .systemGray)
        appendOutput("", color: .systemGray)
    }

    func appendSystemLog(_ text: String) {
        appendOutput("📋 \(text)", color: .systemMint)
    }

    func updateWebView(_ webView: WKWebView?) {
        targetWebView = webView
        appendOutput("// Switched to tab: \(webView?.url?.absoluteString ?? "none")", color: .systemYellow)
    }

    @objc private func quickButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < quickScripts.count else { return }
        let script = quickScripts[index]
        if script.isEmpty {
            clearConsole()
        } else {
            executeJS(script, display: sender.title)
        }
    }

    @objc private func executeInput() {
        let input = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        commandHistory.append(input)
        historyIndex = commandHistory.count
        inputField.stringValue = ""

        executeJS(input, display: input)
    }

    private func executeJS(_ js: String, display: String) {
        appendOutput("❯ \(display)", color: .systemGreen)

        guard let wv = targetWebView else {
            appendOutput("Error: No active WebView", color: .systemRed)
            return
        }

        wv.evaluateJavaScript(js) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.appendOutput("✗ \(error.localizedDescription)", color: .systemRed)
                } else if let result = result {
                    let str = self?.formatResult(result) ?? "\(result)"
                    self?.appendOutput(str, color: .systemCyan)
                } else {
                    self?.appendOutput("undefined", color: .systemGray)
                }
            }
        }
    }

    private func formatResult(_ result: Any) -> String {
        if let str = result as? String { return str }
        if let num = result as? NSNumber { return "\(num)" }
        if let bool = result as? Bool { return bool ? "true" : "false" }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "\(result)"
    }

    private func appendOutput(_ text: String, color: NSColor) {
        let attr = NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ])
        outputTextView.textStorage?.append(attr)
        outputTextView.scrollToEndOfDocument(nil)
    }

    private func clearConsole() {
        outputTextView.textStorage?.setAttributedString(NSAttributedString(string: ""))
    }

    // Arrow key history navigation
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            if !commandHistory.isEmpty {
                historyIndex = max(0, historyIndex - 1)
                inputField.stringValue = commandHistory[historyIndex]
            }
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            if historyIndex < commandHistory.count - 1 {
                historyIndex += 1
                inputField.stringValue = commandHistory[historyIndex]
            } else {
                historyIndex = commandHistory.count
                inputField.stringValue = ""
            }
            return true
        }
        return false
    }
}
