import AppKit
import WebKit
import AVFoundation
import CryptoKit

final class StudioApp: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let queue = DispatchQueue(label: "studio.worker", qos: .userInitiated)
    let control = OperationControl()
    var busy = false
    var store: [String: Any] = [:]
    var root: URL!
    var engine: URL!
    var reference: URL?
    var voice: URL?
    var currentAudio: URL?
    var player: AVAudioPlayer?
    var playbackTimer: Timer?
    var engineReady = false
    var engineMessage = "尚未检查"
    var logText = ""
    var pendingEvents: [(String, Any)] = []
    var ready = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ShengJianStudio")
        // An explicit alternate data directory keeps QA runs away from personal data.
        if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            guard path.hasPrefix("/") else { fatalAlert("测试数据目录必须是绝对路径"); return }
            root = URL(fileURLWithPath: path, isDirectory: true)
        }
        do {
            try mkdir(root)
            for folder in ["Runtime", "Models", "Jobs", "Voices", "References", "Edits"] { try mkdir(root.appendingPathComponent(folder)) }
            store = (try? jsonRead(root.appendingPathComponent("settings.json"))) ?? [:]
        } catch { fatalAlert(error.localizedDescription); return }
        engine = root.appendingPathComponent("Runtime/qwen_tts")
        setupMenu()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "studio")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "声笺 · 本地语音工作室"
        window.minSize = NSSize(width: 1020, height: 720)
        window.contentView = web; window.delegate = self
        window.center(); window.makeKeyAndOrderFront(nil)
        guard let ui = Bundle.main.resourceURL?.appendingPathComponent("ui/index.html") else { fatalAlert("缺少界面资源"); return }
        web.loadFileURL(ui, allowingReadAccessTo: ui.deletingLastPathComponent())
        NSApp.activate(ignoringOtherApps: true)
        #if STUDIO_QA
        DispatchQueue.main.asyncAfter(deadline: .now() + (CommandLine.arguments.contains("--qa-model-dir") ? 300 : 40)) {
            self.control.cancel()
            try? jsonWrite(["passed": false, "error": "Native startup timed out"], self.root.appendingPathComponent("smoke-report.json"))
            exit(2)
        }
        #endif
    }
    func setupMenu() {
        let bar = NSMenu(), appMenu = NSMenu(), appItem = NSMenuItem()
        appItem.submenu = appMenu; bar.addItem(appItem)
        appMenu.addItem(withTitle: "关于声笺", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "退出声笺", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: "编辑"), item = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        item.submenu = edit; bar.addItem(item)
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        NSApp.mainMenu = bar
    }
    @objc func about() {
        let alert = NSAlert(); alert.messageText = "声笺 · Voice Studio 0.1"
        alert.informativeText = "Intel macOS 10.15+ 编译目标。原生 AppKit + 社区 C 推理引擎。\n只在本机处理声音；模型下载可选魔搭或 Hugging Face。\n不包含训练、微调或官方 Python API 的全部功能。\n引擎版本：f1b6865713d12a2a2365282fc02e19a5a384a565\n旧版系统仍需目标机器实测。"
        alert.runModal()
    }
    func fatalAlert(_ message: String) { let alert = NSAlert(); alert.messageText = "无法启动声笺"; alert.informativeText = message; alert.runModal(); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if busy {
            let alert = NSAlert(); alert.messageText = "有任务正在运行，确定退出？"; alert.informativeText = "任务会取消，已经完成的段落和下载文件会保留。"; alert.addButton(withTitle: "退出"); alert.addButton(withTitle: "继续运行")
            if alert.runModal() != .alertFirstButtonReturn { return .terminateCancel }
            control.cancel()
        }
        player?.stop(); return .terminateNow
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.isFileURL,
              let folder = Bundle.main.resourceURL?.appendingPathComponent("ui").standardizedFileURL.path,
              url.standardizedFileURL.path.hasPrefix(folder + "/") else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func emit(_ topic: String, _ value: Any) {
        DispatchQueue.main.async {
            guard self.ready else { self.pendingEvents.append((topic, value)); return }
            guard let data = try? JSONSerialization.data(withJSONObject: ["topic": topic, "data": value]), let text = String(data: data, encoding: .utf8) else { return }
            self.web.evaluateJavaScript("window.receiveNative(\(text));", completionHandler: nil)
        }
    }
    func log(_ text: String) {
        DispatchQueue.main.async {
            self.logText += text
            if self.logText.count > 60000 { self.logText = String(self.logText.suffix(60000)) }
            self.emit("log", text)
        }
    }
    func saveStore() throws { try jsonWrite(store, root.appendingPathComponent("settings.json")) }
    func modelPath(_ spec: ModelSpec) -> URL? {
        let models = store["models"] as? [String: String] ?? [:]
        guard let path = models[spec.id] else { return nil }; return URL(fileURLWithPath: path)
    }
    func state() {
        let models = ModelSpec.catalog.map { spec -> [String: Any] in
            var item = spec.dictionary
            if let url = modelPath(spec) { item["path"] = url.path; item["installed"] = (try? validateModel(url, expected: spec)) != nil }
            else { item["installed"] = false }
            return item
        }
        let jobsRoot = root.appendingPathComponent("Jobs")
        let jobs = ((try? fm.contentsOfDirectory(at: jobsRoot, includingPropertiesForKeys: nil)) ?? []).compactMap { url -> [String: Any]? in
            guard let job = try? jsonRead(url.appendingPathComponent("job.json")), let id = job["id"] as? String else { return nil }
            return ["id": id, "title": job["title"] ?? "未命名", "created": job["created"] ?? "", "status": job["status"] ?? "未知", "count": (job["segments"] as? [[String: Any]])?.count ?? 0]
        }.sorted { ($0["created"] as? String ?? "") > ($1["created"] as? String ?? "") }
        let voices = ((try? fm.contentsOfDirectory(at: root.appendingPathComponent("Voices"), includingPropertiesForKeys: nil)) ?? []).filter { ["bin", "qvoice"].contains($0.pathExtension) }.map { ["name": $0.lastPathComponent, "path": $0.path] }
        let attributes = try? fm.attributesOfFileSystem(forPath: root.path)
        let space = (attributes?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        #if arch(x86_64)
        let arch = "Intel x86_64"
        #else
        let arch = "Apple Silicon（测试构建）"
        #endif
        emit("state", ["models": models, "jobs": jobs, "voices": voices, "settings": store["generation"] ?? [:], "downloadSource": store["downloadSource"] ?? "modelscope", "environment": ["os": ProcessInfo.processInfo.operatingSystemVersionString, "arch": arch, "memoryGB": Double(ProcessInfo.processInfo.physicalMemory) / pow(1024, 3), "cores": ProcessInfo.processInfo.processorCount, "freeGB": space / pow(1024, 3), "ready": engineReady, "message": engineMessage, "root": root.path]])
    }
    func start(_ title: String, task: @escaping () throws -> Void) {
        guard !busy else { emit("error", "已有任务运行中，请等待或取消。"); return }
        busy = true; control.begin(); emit("busy", ["active": true, "title": title]); log("\n— \(title) —\n")
        queue.async {
            do { try task() } catch {
                self.emit("error", error.localizedDescription); self.log("\n\(error.localizedDescription)\n")
                #if STUDIO_QA
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.finishQASmokeTest() }
                #endif
            }
            self.state()
            DispatchQueue.main.async { self.busy = false; self.emit("busy", ["active": false, "title": title]) }
        }
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let data = body["data"] as? [String: Any] ?? [:]
        if action == "ready" {
            ready = true; for (topic, value) in pendingEvents { emit(topic, value) }; pendingEvents = []
            start("首次环境检查与本地运行时准备") {
                try self.prepareRuntime()
                #if STUDIO_QA
                if let index = CommandLine.arguments.firstIndex(of: "--qa-model-dir"), CommandLine.arguments.indices.contains(index + 1),
                   let refIndex = CommandLine.arguments.firstIndex(of: "--qa-reference"), CommandLine.arguments.indices.contains(refIndex + 1) {
                    let model = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                    let ref = URL(fileURLWithPath: CommandLine.arguments[refIndex + 1])
                    let spec = try validateModel(model, expected: ModelSpec.find("base-small"))
                    self.store["models"] = [spec.id: model.path]
                    let settings: [String: Any] = ["modelId": spec.id, "language": "Chinese", "referenceText": "这是一段由电脑生成的测试语音，用来检查本地语音合成程序是否正常工作。", "maxTokens": 128, "threads": 4, "seed": 42, "quantization": "int8", "segmentLength": 80]
                    try self.generate(["text": "你好，这是一次本地测试。", "settings": settings], reference: ref, voice: nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.finishQASmokeTest() }
                #endif
            }; return
        }
        if action == "cancel" { control.cancel(); emit("notice", "正在取消，请等待当前进程退出。"); return }
        if action == "stopAudio" { stopAudio(); return }
        if action == "play" { playAudio(); return }
        if action == "seek" { player?.currentTime = max(0, min(player?.duration ?? 0, (data["seconds"] as? Double) ?? 0)); return }
        if action == "openFolder" { NSWorkspace.shared.open(root.appendingPathComponent("Jobs")); return }
        if action == "openSupport" { NSWorkspace.shared.open(root); return }
        if action == "export" { exportAudio(); return }
        guard !busy else { emit("error", "请先等待当前任务完成，或点击取消。"); return }
        switch action {
        case "check": start("检查与修复运行环境") { try self.prepareRuntime() }
        case "download":
            guard let id = data["id"] as? String else { return }
            start("下载模型") { try self.downloadModel(try ModelSpec.find(id), source: data["source"] as? String ?? "modelscope") }
        case "importModel": chooseDirectory("选择完整的 Qwen3-TTS 模型目录") { url in
            self.start("验证并导入模型") { let spec = try validateModel(url); var models = self.store["models"] as? [String: String] ?? [:]; models[spec.id] = url.path; self.store["models"] = models; try self.saveStore(); self.emit("notice", "已关联 \(spec.name)，没有复制或修改原文件。") }
        }
        case "importText": importText()
        case "reference": importReference()
        case "importVoice": importVoice()
        case "selectVoice":
            let name = data["name"] as? String ?? ""
            guard name == URL(fileURLWithPath: name).lastPathComponent, ["qvoice", "bin"].contains((name as NSString).pathExtension) else { voice = nil; emit("voice", [:]); return }
            let url = root.appendingPathComponent("Voices").appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { voice = url; emit("voice", ["name": name]) }
        case "clearVoice": voice = nil; emit("voice", [:])
        case "generate":
            let ref = reference, savedVoice = voice
            start("生成语音") { try self.generate(data, reference: ref, voice: savedVoice) }
        case "saveVoice":
            let ref = reference
            start("提取并保存声音档案") { try self.saveVoice(data, reference: ref) }
        case "loadJob":
            start("打开项目") { let (folder, job) = try self.job(data); self.emit("job", job); let file = folder.appendingPathComponent("combined.wav"); if fm.fileExists(atPath: file.path) { try self.setAudio(file) } }
        case "previewSegment":
            start("载入音频") { let (folder, job) = try self.job(data); let segments = job["segments"] as? [[String: Any]] ?? []; guard let index = data["index"] as? Int, segments.indices.contains(index), segments[index]["status"] as? String == "done" else { throw fail("该段还没有音频") }; try self.setAudio(folder.appendingPathComponent(String(format: "segment-%03d.wav", index))) }
        case "regenerate": start("重新生成段落") { try self.regenerate(data) }
        case "editAudio":
            let audio = currentAudio
            start("处理音频副本") { guard let audio = audio else { throw fail("请先选择一段生成音频") }; try self.editAudio(audio, data) }
        case "saveSettings":
            queue.async { self.store["generation"] = data; do { try self.saveStore(); self.emit("notice", "参数预设已保存。") } catch { self.emit("error", error.localizedDescription) } }
        case "refresh": queue.async { self.state() }
        default: emit("error", "不支持的操作")
        }
    }
    func chooseDirectory(_ title: String, done: @escaping (URL) -> Void) {
        let panel = NSOpenPanel(); panel.title = title; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { result in if result == .OK, let url = panel.url { done(url) } }
    }
    func chooseFiles(_ title: String, types: [String], multiple: Bool = false, done: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel(); panel.title = title; panel.allowedFileTypes = types; panel.allowsMultipleSelection = multiple
        panel.beginSheetModal(for: window) { result in if result == .OK { done(panel.urls) } }
    }
    func prepareRuntime() throws {
        engineReady = false
        engineMessage = "检查未完成；失败详情请查看下方诊断日志"
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)) else { throw fail("系统低于 macOS 10.15，程序不会自行升级操作系统。") }
        guard let resources = Bundle.main.resourceURL else { throw fail("应用资源丢失，请重新解压安装包") }
        func install(_ name: String, checksumFile: String) throws -> URL {
            let bundled = resources.appendingPathComponent("engine/" + name)
            let expected = try String(contentsOf: resources.appendingPathComponent("engine/" + checksumFile), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard try sha256(bundled) == expected else { throw fail("应用内的推理引擎校验失败，请重新获取原始安装包。") }
            let destination = root.appendingPathComponent("Runtime/" + name)
            if (try? sha256(destination)) != expected {
                let temp = destination.appendingPathExtension("installing")
                if fm.fileExists(atPath: temp.path) { try fm.removeItem(at: temp) }
                try fm.copyItem(at: bundled, to: temp)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)
                if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: temp) }
                else { try fm.moveItem(at: temp, to: destination) }
                log("已从应用内安装经过 SHA-256 校验的引擎：\(name)。无需管理员权限。\n")
            }
            return destination
        }
        engine = try install("qwen_tts", checksumFile: "sha256.txt")
        let caps = try runProcess(engine, ["--caps"], control: control, log: log)
        let compatible = caps.contains("will SIGILL")
        if compatible {
            log("当前 CPU 环境未报告 AVX2，自动选用应用内的 CPU 兼容引擎。该模式可能较慢。\n")
            engine = try install("qwen_tts_compatible", checksumFile: "compatible-sha256.txt")
            try runProcess(engine, ["--caps"], control: control, log: log)
            try runProcess(engine, ["--self-test"], control: control, log: log)
        }
        try control.check()
        guard fm.isExecutableFile(atPath: "/usr/bin/afconvert") else { throw fail("系统缺少音频转换组件 afconvert，无法自动安装系统组件，请修复 macOS。") }
        engineReady = true; engineMessage = compatible ? "引擎就绪 · CPU 兼容模式 / Accelerate" : "引擎就绪 · AVX2 / Accelerate"
        if ProcessInfo.processInfo.physicalMemory < 8 * 1024 * 1024 * 1024 { engineMessage += " · 内存偏低，建议 0.6B 短句测试" }
        log("环境检查完成。缺失或损坏的私有运行时已自动修复；没有更改系统 Python。\n")
    }
    func downloadModel(_ spec: ModelSpec, source: String) throws {
        let folder = root.appendingPathComponent("Models").appendingPathComponent(spec.id)
        try downloadModelFiles(spec, source: source, folder: folder, control: control, log: log) { label, fraction in self.emit("progress", ["label": label, "fraction": fraction]) }
        var models = store["models"] as? [String: String] ?? [:]; models[spec.id] = folder.path; store["models"] = models
        store["downloadSource"] = source
        try saveStore(); emit("notice", "\(spec.name) 已可离线使用。")
    }
    func importText() {
        chooseFiles("导入文本（多个文件按选择顺序合并）", types: ["txt", "md", "rtf"], multiple: true) { urls in
            self.start("读取文本文件") {
                var texts: [String] = []
                for url in urls {
                    guard fileSize(url) < 5 * 1024 * 1024 else { throw fail("文本文件超过 5MB，请拆分后导入") }
                    if url.pathExtension.lowercased() == "rtf" { texts.append(try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string) }
                    else {
                        let bytes = try Data(contentsOf: url)
                        texts.append(try decodeText(bytes))
                    }
                }
                self.emit("text", ["text": texts.joined(separator: "\n\n"), "name": urls.map { $0.lastPathComponent }.joined(separator: "、")])
            }
        }
    }
    func importReference() {
        chooseFiles("选择自己的参考录音", types: ["wav", "m4a", "mp3", "aiff", "aif", "caf", "flac"]) { urls in
            guard let source = urls.first else { return }
            self.start("转换参考录音为 24kHz 单声道 WAV") {
                let audio = try AVAudioFile(forReading: source)
                guard Double(audio.length) / audio.processingFormat.sampleRate <= 180 else { throw fail("参考录音暂限三分钟，请先裁剪为干净的人声片段。") }
                let target = self.root.appendingPathComponent("References/\(UUID().uuidString).wav")
                try runProcess(URL(fileURLWithPath: "/usr/bin/afconvert"), ["-f", "WAVE", "-d", "LEI16@24000", "-c", "1", source.path, target.path], control: self.control, log: self.log)
                let pcm = try PCM.read(target)
                guard pcm.duration >= 3 else { throw fail("参考录音少于三秒，请使用更长的人声录音。") }
                DispatchQueue.main.async { self.reference = target; self.voice = nil }
                self.emit("reference", ["name": source.lastPathComponent, "duration": pcm.duration, "waveform": pcm.waveform]); self.emit("voice", [:])
            }
        }
    }
    func importVoice() {
        chooseFiles("选择自己保存的声音档案（仅导入可信文件）", types: ["bin", "qvoice"]) { urls in
            guard let url = urls.first else { return }
            self.start("导入声音档案") {
                try validateVoice(url)
                let target = self.root.appendingPathComponent("Voices/\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)")
                try fm.copyItem(at: url, to: target)
                DispatchQueue.main.async { self.voice = target }; self.emit("voice", ["name": target.lastPathComponent])
            }
        }
    }
    func checkedModel(_ settings: [String: Any]) throws -> (ModelSpec, URL) {
        guard engineReady else { throw fail("推理引擎未就绪，请先到环境设置检查。") }
        let spec = try ModelSpec.find(settings["modelId"] as? String ?? "base-small")
        guard let model = modelPath(spec) else { throw fail("请先在“模型管理”下载或导入 \(spec.name)") }
        _ = try validateModel(model, expected: spec); return (spec, model)
    }
    func generate(_ data: [String: Any], reference: URL?, voice: URL?) throws {
        let settings = data["settings"] as? [String: Any] ?? [:]
        let (spec, model) = try checkedModel(settings)
        let text = data["text"] as? String ?? ""
        let limit = Int(try number(settings, "segmentLength", 180, 30...600))
        let texts = splitText(text, limit: limit)
        guard !texts.isEmpty, texts.count <= 300 else { throw fail("请输入文本；一个项目最多 300 段。") }
        let folder = root.appendingPathComponent("Jobs/\(UUID().uuidString)")
        // Validate settings before creating a project, including a required reference transcript.
        _ = try engineArguments(spec: spec, model: model, text: texts[0], output: folder.appendingPathComponent("probe.wav"), settings: settings, reference: reference, voice: voice)
        try mkdir(folder)
        let refCopy = reference.map { _ in folder.appendingPathComponent("reference.wav") }
        if let ref = reference, let copy = refCopy { try fm.copyItem(at: ref, to: copy) }
        let voiceCopy = voice.map { folder.appendingPathComponent("voice.\($0.pathExtension)") }
        if let original = voice, let copy = voiceCopy { try fm.copyItem(at: original, to: copy) }
        var segments: [[String: Any]] = texts.enumerated().map { ["index": $0.offset, "text": $0.element, "status": "pending"] }
        var job: [String: Any] = ["id": folder.lastPathComponent, "title": String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)), "created": ISO8601DateFormatter().string(from: Date()), "status": "running", "settings": settings, "segments": segments]
        if let ref = refCopy { job["reference"] = ref.lastPathComponent }; if let v = voiceCopy { job["voice"] = v.lastPathComponent }
        try jsonWrite(job, folder.appendingPathComponent("job.json")); emit("job", job)
        do {
            for i in texts.indices {
                try control.check(); segments[i]["status"] = "running"; job["segments"] = segments; emit("job", job)
                emit("progress", ["fraction": Double(i) / Double(texts.count), "label": "生成第 \(i + 1) / \(texts.count) 段"])
                let output = folder.appendingPathComponent(String(format: "segment-%03d.wav", i))
                let temp = folder.appendingPathComponent("rendering.wav")
                try runProcess(engine, try engineArguments(spec: spec, model: model, text: texts[i], output: temp, settings: settings, reference: refCopy, voice: voiceCopy), cwd: Bundle.main.resourceURL?.appendingPathComponent("engine"), control: control, log: log)
                let pcm = try PCM.read(temp)
                guard pcm.duration > 0.1 else { throw fail("模型未生成有效音频") }
                try fm.moveItem(at: temp, to: output)
                segments[i]["status"] = "done"; segments[i]["duration"] = pcm.duration; job["segments"] = segments
                try jsonWrite(job, folder.appendingPathComponent("job.json")); emit("job", job)
            }
            try mergeJob(folder, job)
            job["status"] = "done"; try jsonWrite(job, folder.appendingPathComponent("job.json")); emit("job", job)
            try setAudio(folder.appendingPathComponent("combined.wav")); emit("progress", ["fraction": 1, "label": "全部生成完成"])
            store["generation"] = settings; try saveStore()
        } catch {
            for i in segments.indices where segments[i]["status"] as? String == "running" { segments[i]["status"] = "pending" }
            job["segments"] = segments; job["status"] = control.isCancelled ? "cancelled" : "failed"
            try? jsonWrite(job, folder.appendingPathComponent("job.json")); emit("job", job); throw error
        }
    }
    func job(_ data: [String: Any]) throws -> (URL, [String: Any]) {
        guard let id = data["id"] as? String, UUID(uuidString: id) != nil else { throw fail("无效项目编号") }
        let folder = root.appendingPathComponent("Jobs").appendingPathComponent(id)
        return (folder, try jsonRead(folder.appendingPathComponent("job.json")))
    }
    func mergeJob(_ folder: URL, _ job: [String: Any]) throws {
        let segments = job["segments"] as? [[String: Any]] ?? []
        guard !segments.isEmpty, segments.allSatisfy({ $0["status"] as? String == "done" }) else { return }
        let parts = try segments.indices.map { try PCM.read(folder.appendingPathComponent(String(format: "segment-%03d.wav", $0))) }
        let settings = job["settings"] as? [String: Any] ?? [:]
        let gap = try number(settings, "gap", 0.3, 0...5)
        try PCM.join(parts, gap: gap).write(folder.appendingPathComponent("combined.wav"))
    }
    func regenerate(_ data: [String: Any]) throws {
        var (folder, saved) = try job(data)
        var segments = saved["segments"] as? [[String: Any]] ?? []
        guard let i = data["index"] as? Int, segments.indices.contains(i), let text = data["text"] as? String, !text.isEmpty else { throw fail("无效段落") }
        let settings = data["settings"] as? [String: Any] ?? saved["settings"] as? [String: Any] ?? [:]
        let originalSettings = saved["settings"] as? [String: Any] ?? [:]
        guard settings["modelId"] as? String == originalSettings["modelId"] as? String else { throw fail("逐段重生成请保持原模型。切换模型时请创建新项目。") }
        let (spec, model) = try checkedModel(settings)
        let ref = (saved["reference"] as? String).map { folder.appendingPathComponent($0) }
        let v = (saved["voice"] as? String).map { folder.appendingPathComponent($0) }
        let temp = folder.appendingPathComponent("rerender.wav"), output = folder.appendingPathComponent(String(format: "segment-%03d.wav", i))
        try runProcess(engine, try engineArguments(spec: spec, model: model, text: text, output: temp, settings: settings, reference: ref, voice: v), cwd: Bundle.main.resourceURL?.appendingPathComponent("engine"), control: control, log: log)
        let pcm = try PCM.read(temp); guard pcm.duration > 0.1 else { throw fail("模型没有生成有效音频") }
        if fm.fileExists(atPath: output.path) { _ = try fm.replaceItemAt(output, withItemAt: temp) } else { try fm.moveItem(at: temp, to: output) }
        segments[i]["text"] = text; segments[i]["status"] = "done"; segments[i]["duration"] = pcm.duration; segments[i]["settings"] = settings
        saved["segments"] = segments
        saved["status"] = segments.allSatisfy { $0["status"] as? String == "done" } ? "done" : "partial"
        try jsonWrite(saved, folder.appendingPathComponent("job.json")); try mergeJob(folder, saved); emit("job", saved)
        try setAudio(output)
    }
    func saveVoice(_ data: [String: Any], reference: URL?) throws {
        let settings = data["settings"] as? [String: Any] ?? [:]
        let (spec, model) = try checkedModel(settings)
        guard spec.kind == "base", let reference = reference else { throw fail("保存声音档案需要 Base 模型和参考录音") }
        let vector = settings["xvector"] as? Bool ?? false
        let name = String((data["name"] as? String ?? "我的声音").filter { !$0.isNewline && $0 != "/" && $0 != ":" }.prefix(40))
        let target = root.appendingPathComponent("Voices/\(name.isEmpty ? "我的声音" : name)-\(UUID().uuidString.prefix(8)).\(vector ? "bin" : "qvoice")")
        let partial = target.deletingLastPathComponent().appendingPathComponent("partial-\(target.lastPathComponent)")
        var args = ["-d", model.path, "--ref-audio", reference.path, "--save-voice", partial.path, "--voice-name", name, "--language", settings["language"] as? String ?? "Chinese", "--max-ref-duration", String(try number(settings, "maxReference", 30, 3...120))]
        if vector { args.append("--xvector-only") }
        else { let text = settings["referenceText"] as? String ?? ""; guard !text.isEmpty else { throw fail("请填写参考录音对应文字") }; args += ["--ref-text", text] }
        do {
            try runProcess(engine, args, cwd: Bundle.main.resourceURL?.appendingPathComponent("engine"), control: control, log: log)
            guard fileSize(partial) > 0 else { throw fail("声音档案未生成") }
            try fm.moveItem(at: partial, to: target)
        } catch { try? fm.removeItem(at: partial); throw error }
        DispatchQueue.main.async { self.voice = target }; emit("voice", ["name": target.lastPathComponent]); emit("notice", "声音档案已保存。再次使用时请选择相同大小的模型。")
    }
    func setAudio(_ url: URL) throws {
        let pcm = try PCM.read(url)
        DispatchQueue.main.async { self.stopAudio(); self.currentAudio = url }
        emit("audio", ["name": url.lastPathComponent, "duration": pcm.duration, "waveform": pcm.waveform])
    }
    func playAudio() {
        guard let audio = currentAudio else { emit("error", "还没有可试听的音频"); return }
        do {
            if player?.isPlaying == true { player?.pause(); emit("playback", ["playing": false, "time": player?.currentTime ?? 0]); return }
            if player == nil { player = try AVAudioPlayer(contentsOf: audio) }
            player?.play(); playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in self.emit("playback", ["playing": self.player?.isPlaying ?? false, "time": self.player?.currentTime ?? 0]) }
        } catch { emit("error", error.localizedDescription) }
    }
    func stopAudio() { playbackTimer?.invalidate(); player?.stop(); player = nil; emit("playback", ["playing": false, "time": 0]) }
    func exportAudio() {
        guard let source = currentAudio else { emit("error", "请先生成或选择音频"); return }
        let panel = NSSavePanel(); panel.allowedFileTypes = ["wav"]; panel.nameFieldStringValue = "声笺-\(source.lastPathComponent)"
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url {
                do { try Data(contentsOf: source).write(to: url, options: .atomic); self.emit("notice", "音频已导出。") } catch { self.emit("error", error.localizedDescription) }
            }
        }
    }
    func editAudio(_ input: URL, _ data: [String: Any]) throws {
        let source = try PCM.read(input)
        let edit = try source.edited(start: number(data, "start", 0, 0...7200), end: number(data, "end", 0, 0...7200), gain: number(data, "gain", 0, -24...12), normalize: data["normalize"] as? Bool ?? false, fade: number(data, "fade", 0.03, 0...2))
        let folder = root.appendingPathComponent("Edits/\(UUID().uuidString)"); try mkdir(folder)
        let before = folder.appendingPathComponent("trimmed.wav"), intermediate = folder.appendingPathComponent("pitched.caf"), output = folder.appendingPathComponent("adjusted.wav")
        try edit.write(before)
        try timePitch(before, intermediate, rate: Float(number(data, "rate", 1, 0.5...2)), pitch: Float(number(data, "pitch", 0, -12...12)), control: control)
        try PCM.read(intermediate).write(output)
        try? fm.removeItem(at: before); try? fm.removeItem(at: intermediate)
        try setAudio(output); emit("notice", "已创建调整后的副本，原始生成音频未改变。")
    }
    #if STUDIO_QA
    func finishQASmokeTest() {
        try? logText.write(to: root.appendingPathComponent("diagnostic.log"), atomically: true, encoding: .utf8)
        web.evaluateJavaScript("({title:document.title,models:document.querySelectorAll('#modelGrid article').length,badge:document.getElementById('environmentBadge').textContent,buttons:document.querySelectorAll('button').length})") { result, error in
            var report: [String: Any] = ["engineReady": self.engineReady, "os": ProcessInfo.processInfo.operatingSystemVersionString, "dom": result ?? [:], "error": error?.localizedDescription ?? "", "passed": self.engineReady && error == nil]
            if let dom = result as? [String: Any] { report["passed"] = self.engineReady && (dom["models"] as? Int == 5) }
            if CommandLine.arguments.contains("--qa-model-dir") {
                let directories = (try? fm.contentsOfDirectory(at: self.root.appendingPathComponent("Jobs"), includingPropertiesForKeys: nil)) ?? []
                let jobs = directories.compactMap { try? jsonRead($0.appendingPathComponent("job.json")) }
                let generated = !jobs.isEmpty && jobs.allSatisfy { $0["status"] as? String == "done" }
                report["generationPassed"] = generated
                report["passed"] = (report["passed"] as? Bool == true) && generated
            }
            try? jsonWrite(report, self.root.appendingPathComponent("smoke-report.json"))
            self.web.takeSnapshot(with: nil) { image, error in
                if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: self.root.appendingPathComponent("native-interface.png")) }
                exit((report["passed"] as? Bool == true) ? 0 : 1)
            }
        }
    }
    #endif
}
