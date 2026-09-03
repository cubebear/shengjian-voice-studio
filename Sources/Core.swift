import Foundation
import CryptoKit
import AVFoundation

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
func fail(_ text: String) -> StudioError { .message(text) }
let fm = FileManager.default
func mkdir(_ url: URL) throws { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
func jsonRead(_ url: URL) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else { throw fail("JSON 格式无效：\(url.lastPathComponent)") }
    return value
}
func jsonWrite(_ value: Any, _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
}
func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while true { let part = handle.readData(ofLength: 4 * 1024 * 1024); if part.isEmpty { break }; hash.update(data: part) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func fileSize(_ url: URL) -> Int64 { ((try? fm.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0 }
func number(_ data: [String: Any], _ key: String, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
    let value = (data[key] as? NSNumber)?.doubleValue ?? fallback
    guard value.isFinite, range.contains(value) else { throw fail("参数 \(key) 超出允许范围 \(range)") }
    return value
}

func decodeText(_ bytes: Data) throws -> String {
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    let hasUTF16BOM = bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff])
    let value = hasUTF16BOM ? String(data: bytes, encoding: .utf16) : (String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: gb))
    guard let text = value, !text.contains("\0") else { throw fail("无法识别文本编码，请保存为 UTF-8 或带 BOM 的 UTF-16") }
    return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
}

@discardableResult
func validateVoice(_ url: URL, spec: ModelSpec? = nil) throws -> Int {
    guard fileSize(url) < 100 * 1024 * 1024 else { throw fail("声音档案超过 100MB；不支持含完整权重的旧档案。") }
    let data = try Data(contentsOf: url)
    var cursor = 0
    func u32() throws -> Int {
        guard cursor + 4 <= data.count else { throw fail("声音档案不完整") }
        defer { cursor += 4 }
        return (0..<4).reduce(0) { $0 | Int(data[cursor + $1]) << (8 * $1) }
    }
    let dim: Int
    if url.pathExtension.lowercased() == "bin" {
        guard [4096, 8192].contains(data.count) else { throw fail("音色向量必须是 4096 或 8192 字节") }
        dim = data.count / 4
    } else {
        guard data.prefix(4) == Data("QVCE".utf8) else { throw fail("不是有效的 QVCE 声音档案") }
        cursor = 4
        let version = try u32()
        guard [2, 3].contains(version) else { throw fail("只支持带尺寸信息的 .qvoice v2/v3，请使用 Base 模型重新提取。") }
        dim = try u32()
        guard [1024, 2048].contains(dim) else { throw fail("声音档案尺寸不受支持") }
        cursor += dim * 4
        let textLength = try u32()
        guard textLength <= 100000, cursor + textLength <= data.count else { throw fail("声音档案文字长度无效") }
        cursor += textLength
        let frames = try u32()
        guard frames <= 15000, cursor + frames * 64 <= data.count else { throw fail("声音档案的参考音频数据不完整或过长") }
    }
    if let spec = spec, dim != (spec.size == "0.6B" ? 1024 : 2048) { throw fail("声音档案与模型大小不同。0.6B 和 1.7B 档案不能混用。") }
    return dim
}

struct ModelSpec {
    let id: String, name: String, kind: String, size: String, repo: String
    var dictionary: [String: Any] { ["id": id, "name": name, "kind": kind, "size": size, "repo": repo] }
    static let catalog = [
        ModelSpec(id: "base-small", name: "Qwen3-TTS · 0.6B Base", kind: "base", size: "0.6B", repo: "Qwen/Qwen3-TTS-12Hz-0.6B-Base"),
        ModelSpec(id: "base-large", name: "Qwen3-TTS · 1.7B Base", kind: "base", size: "1.7B", repo: "Qwen/Qwen3-TTS-12Hz-1.7B-Base"),
        ModelSpec(id: "custom-small", name: "Qwen3-TTS · 0.6B CustomVoice", kind: "custom_voice", size: "0.6B", repo: "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"),
        ModelSpec(id: "custom-large", name: "Qwen3-TTS · 1.7B CustomVoice", kind: "custom_voice", size: "1.7B", repo: "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice"),
        ModelSpec(id: "design", name: "Qwen3-TTS · 1.7B VoiceDesign", kind: "voice_design", size: "1.7B", repo: "Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign")
    ]
    static let files = ["config.json", "generation_config.json", "tokenizer_config.json", "preprocessor_config.json", "model.safetensors", "vocab.json", "merges.txt", "speech_tokenizer/config.json", "speech_tokenizer/configuration.json", "speech_tokenizer/model.safetensors", "speech_tokenizer/preprocessor_config.json"]
    static func find(_ id: String) throws -> ModelSpec {
        guard let s = catalog.first(where: { $0.id == id }) else { throw fail("未知模型") }; return s
    }
}

// Only header and tensor bounds are inspected; importing a model never executes code.
func validateSafetensors(_ url: URL) throws {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let prefix = handle.readData(ofLength: 8)
    guard prefix.count == 8 else { throw fail("权重文件不完整：\(url.lastPathComponent)") }
    let length = prefix.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
    let bytes = UInt64(fileSize(url))
    guard length > 2, length < 64 * 1024 * 1024, bytes > length + 8 else { throw fail("不是有效的 safetensors 权重，可能是未下载的 Git LFS 指针。") }
    let header = handle.readData(ofLength: Int(length))
    guard let tensors = try JSONSerialization.jsonObject(with: header) as? [String: Any] else { throw fail("权重头部无效") }
    var count = 0
    for (key, value) in tensors where key != "__metadata__" {
        guard let tensor = value as? [String: Any], let offsets = tensor["data_offsets"] as? [NSNumber], offsets.count == 2,
              offsets[0].int64Value >= 0, offsets[1].int64Value >= offsets[0].int64Value,
              offsets[1].uint64Value <= bytes - length - 8,
              let dtype = tensor["dtype"] as? String, ["BF16", "F32", "F16", "I64", "I32", "BOOL"].contains(dtype)
        else { throw fail("权重数据不完整或量化格式不受支持：\(key)") }
        count += 1
    }
    guard count > 0 else { throw fail("权重文件没有张量") }
}

func validateModel(_ url: URL, expected: ModelSpec? = nil) throws -> ModelSpec {
    for path in ModelSpec.files where fileSize(url.appendingPathComponent(path)) < 1 { throw fail("模型目录缺少 \(path)。请选择完整的官方模型文件夹，不是单个权重或 MLX/GGUF 文件。") }
    let config = try jsonRead(url.appendingPathComponent("config.json"))
    guard config["quantization_config"] == nil,
          let kind = config["tts_model_type"] as? String,
          let talker = config["talker_config"] as? [String: Any],
          let hidden = talker["hidden_size"] as? Int,
          let spec = ModelSpec.catalog.first(where: { $0.kind == kind && $0.size == (hidden == 1024 ? "0.6B" : "1.7B") }),
          [1024, 2048].contains(hidden) else { throw fail("不支持此模型架构。当前只支持 Qwen3-TTS 12Hz 官方 BF16 模型目录。") }
    if let expected = expected, expected.id != spec.id { throw fail("模型类型与所选项目不一致：实际是 \(spec.name)") }
    try validateSafetensors(url.appendingPathComponent("model.safetensors"))
    try validateSafetensors(url.appendingPathComponent("speech_tokenizer/model.safetensors"))
    return spec
}

final class OperationControl {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    func begin() { lock.lock(); stopped = false; process = nil; lock.unlock() }
    func check() throws { lock.lock(); let value = stopped; lock.unlock(); if value { throw fail("操作已取消，已完成的文件会保留。") } }
    func attach(_ p: Process) throws { lock.lock(); defer { lock.unlock() }; if stopped { throw fail("操作已取消") }; process = p }
    func detach() { lock.lock(); process = nil; lock.unlock() }
    func cancel() {
        lock.lock(); stopped = true; let current = process
        // Synchronize process lifetime with detachment to avoid signaling a recycled PID.
        if let p = current, p.isRunning { p.terminate() }
        lock.unlock()
    }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

@discardableResult
func runProcess(_ executable: URL, _ arguments: [String], cwd: URL? = nil, control: OperationControl? = nil, log: @escaping (String) -> Void = { _ in }) throws -> String {
    try control?.check()
    let process = Process(), pipe = Pipe()
    process.executableURL = executable; process.arguments = arguments; process.currentDirectoryURL = cwd
    process.standardOutput = pipe; process.standardError = pipe
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "en_US.UTF-8"; environment["VECLIB_MAXIMUM_THREADS"] = "4"
    process.environment = environment
    try control?.attach(process)
    defer { control?.detach() }
    try process.run()
    if control?.isCancelled == true { process.terminate() }
    var output = Data()
    while true {
        let data = pipe.fileHandleForReading.availableData
        if data.isEmpty { break }
        output.append(data)
        if output.count > 128 * 1024 { output.removeFirst(output.count - 128 * 1024) }
        log(String(decoding: data, as: UTF8.self))
    }
    process.waitUntilExit()
    try control?.check()
    let text = String(decoding: output, as: UTF8.self)
    guard process.terminationStatus == 0 else { throw fail("进程退出（\(process.terminationStatus)）：\n\(text.suffix(2500))") }
    return text
}

func splitText(_ text: String, limit: Int) -> [String] {
    let clean = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    var result: [String] = [], buffer = ""
    let marks: Set<Character> = ["。", "！", "？", "!", "?", ";", "；", "\n"]
    func flush() { let s = buffer.trimmingCharacters(in: .whitespacesAndNewlines); if !s.isEmpty { result.append(s) }; buffer = "" }
    for character in clean {
        buffer.append(character)
        if buffer.count >= limit || (marks.contains(character) && buffer.count >= max(12, limit / 3)) || character == "\n" { flush() }
    }
    flush(); return result
}

struct PCM {
    let rate: Int
    var samples: [Float]
    var duration: Double { Double(samples.count) / Double(rate) }
    static func read(_ url: URL) throws -> PCM {
        let audio = try AVAudioFile(forReading: url)
        guard audio.length > 0, audio.length < 24000 * 60 * 120, audio.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 32768) else { throw fail("音频为空、过长或不是单声道。") }
        var samples: [Float] = []; samples.reserveCapacity(Int(audio.length))
        while audio.framePosition < audio.length {
            try audio.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            guard let data = buffer.floatChannelData else { throw fail("无法读取音频采样") }
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        }
        guard !samples.isEmpty else { throw fail("音频解码没有产生采样") }
        return PCM(rate: Int(audio.processingFormat.sampleRate), samples: samples)
    }
    func write(_ url: URL) throws {
        guard rate > 0, samples.count < Int(UInt32.max / 2) - 22 else { throw fail("音频超过 WAV 格式大小限制") }
        var data = Data()
        func str(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) { for i in 0..<4 { data.append(UInt8((value >> (i * 8)) & 255)) } }
        str("RIFF"); u32(UInt32(36 + samples.count * 2)); str("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16); str("data"); u32(UInt32(samples.count * 2))
        for value in samples { let v = value.isFinite ? value : 0; u16(UInt16(bitPattern: Int16(max(-32768, min(32767, Int((v * 32767).rounded())))))) }
        try data.write(to: url, options: .atomic)
    }
    var waveform: [Double] {
        let stride = max(1, samples.count / 120)
        return (0..<min(120, samples.count)).map { index in
            let start = index * stride, end = min(samples.count, start + stride)
            return samples[start..<end].reduce(0.0) { max($0, Double(abs($1))) }
        }
    }
    func edited(start: Double, end: Double, gain: Double, normalize: Bool, fade: Double) throws -> PCM {
        let stop = end == 0 ? duration : end
        guard start.isFinite, stop.isFinite, gain.isFinite, fade.isFinite, start >= 0, stop > start, stop <= duration + 0.01, (-24...12).contains(gain), (0...2).contains(fade) else { throw fail("裁剪或音量参数无效，结束时间必须晚于开始时间。") }
        let lo = min(samples.count, Int(start * Double(rate))), hi = min(samples.count, Int(stop * Double(rate)))
        var output = Array(samples[lo..<hi])
        let peak = output.reduce(Float(0)) { max($0, abs($1)) }
        let multiplier = Float(pow(10, gain / 20)) * (normalize && peak > 0 ? 0.95 / peak : 1)
        let fadeFrames = min(output.count / 2, Int(fade * Double(rate)))
        for i in output.indices {
            var scale = multiplier
            if fadeFrames > 0 { scale *= min(1, Float(min(i, output.count - 1 - i)) / Float(fadeFrames)) }
            output[i] = max(-1, min(1, output[i] * scale))
        }
        return PCM(rate: rate, samples: output)
    }
    static func join(_ parts: [PCM], gap: Double) throws -> PCM {
        guard let first = parts.first, gap.isFinite, (0...5).contains(gap), parts.allSatisfy({ $0.rate == first.rate }) else { throw fail("合并音频的采样率或间隔无效") }
        let total = parts.reduce(0) { $0 + $1.samples.count } + max(0, parts.count - 1) * Int(gap * Double(first.rate))
        guard total < first.rate * 60 * 120 else { throw fail("单个项目暂限两小时，请拆分文本。") }
        var samples: [Float] = []; samples.reserveCapacity(total)
        for (index, part) in parts.enumerated() {
            if index > 0 { samples.append(contentsOf: repeatElement(0, count: Int(gap * Double(first.rate)))) }
            samples.append(contentsOf: part.samples)
        }
        return PCM(rate: first.rate, samples: samples)
    }
}

func timePitch(_ input: URL, _ output: URL, rate: Float, pitch: Float, control: OperationControl) throws {
    guard (0.5...2).contains(rate), (-12...12).contains(pitch) else { throw fail("语速或音高超出范围") }
    if rate == 1 && pitch == 0 { try fm.copyItem(at: input, to: output); return }
    var component = AudioComponentDescription(componentType: kAudioUnitType_FormatConverter, componentSubType: kAudioUnitSubType_NewTimePitch, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    guard AudioComponentFindNext(nil, &component) != nil else { throw fail("系统音高处理组件不可用。请在正常桌面会话中运行；必要时重新启动 macOS。") }
    try autoreleasepool {
    let file = try AVAudioFile(forReading: input)
    let engine = AVAudioEngine(), player = AVAudioPlayerNode(), effect = AVAudioUnitTimePitch()
    effect.rate = rate; effect.pitch = pitch * 100
    engine.attach(player); engine.attach(effect)
    engine.connect(player, to: effect, format: file.processingFormat)
    engine.connect(effect, to: engine.mainMixerNode, format: file.processingFormat)
    try engine.enableManualRenderingMode(.offline, format: file.processingFormat, maximumFrameCount: 4096)
    let outFile = try AVAudioFile(forWriting: output, settings: file.processingFormat.settings)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { throw fail("无法分配音频缓冲") }
    player.scheduleFile(file, at: nil)
    try engine.start(); player.play()
    defer { player.stop(); engine.stop(); engine.disableManualRenderingMode() }
    let frames = AVAudioFramePosition(ceil(Double(file.length) / Double(rate)))
    var failures = 0
    var written: AVAudioFramePosition = 0
    while written < frames {
        try control.check()
        let remaining = frames - written
        let status = try engine.renderOffline(AVAudioFrameCount(min(4096, remaining)), to: buffer)
        switch status {
        case .success:
            if buffer.frameLength > 0 { try outFile.write(from: buffer); written += AVAudioFramePosition(buffer.frameLength); failures = 0 }
            else { failures += 1; if failures > 200 { throw fail("音频处理没有产生采样") } }
        case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
            failures += 1; if failures > 200 { throw fail("离线音频处理未取得进展") }
        case .error: throw fail("离线音频处理失败")
        @unknown default: throw fail("未知音频处理状态")
        }
    }
    } // Drain AVAudioFile's autoreleased writer before the caller reopens its output.
}

func engineArguments(spec: ModelSpec, model: URL, text: String, output: URL, settings: [String: Any], reference: URL?, voice: URL?) throws -> [String] {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count < 32000 else { throw fail("段落为空或过长") }
    if let voice = voice, spec.kind != "voice_design" { try validateVoice(voice, spec: spec) }
    let language = settings["language"] as? String ?? "Chinese"
    guard ["Chinese", "English", "Japanese", "Korean", "German", "French", "Russian", "Portuguese", "Spanish", "Italian"].contains(language) else { throw fail("不支持的语种") }
    var args = ["--model-dir", model.path, "--text", text, "--output", output.path, "--language", language,
                "--temperature", String(try number(settings, "temperature", 0.7, 0.01...2)),
                "--top-k", String(Int(try number(settings, "topK", 50, 1...1024))),
                "--top-p", String(try number(settings, "topP", 0.95, 0.01...1)),
                "--rep-penalty", String(try number(settings, "repetition", 1.05, 0.5...2)),
                "--max-tokens", String(Int(try number(settings, "maxTokens", 2048, 64...8192))),
                "--threads", String(Int(try number(settings, "threads", 4, 1...64))),
                "--rate", String(try number(settings, "rate", 1, 0.5...2)),
                "--volume", String(try number(settings, "volume", 1, 0.1...2))]
    let seed = try number(settings, "seed", -1, -1...2147483647)
    if seed >= 0 { args += ["--seed", String(Int(seed))] }
    switch settings["quantization"] as? String ?? "int8" {
    case "int8": args.append("--int8")
    case "int4": args.append("--int4")
    case "mixed": args.append("--quant-mixed-cpu")
    case "bf16": break
    default: throw fail("不支持的精度选项")
    }
    let instruction = settings["instruction"] as? String ?? ""
    if spec.kind == "base" {
        if let voice = voice { args += ["--load-voice", voice.path] }
        else if let reference = reference {
            args += ["--ref-audio", reference.path, "--max-ref-duration", String(try number(settings, "maxReference", 30, 3...120))]
            if settings["xvector"] as? Bool == true { args.append("--xvector-only") }
            else {
                let transcript = (settings["referenceText"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !transcript.isEmpty else { throw fail("完整克隆需要参考录音对应文字；也可以选择“仅音色向量”模式。") }
                args += ["--ref-text", transcript]
            }
        } else { throw fail("请导入参考录音或选择保存的声音档案") }
    } else if spec.kind == "voice_design" {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail("请填写音色设计描述") }
        args += ["--voice-design", "--instruct", instruction]
    } else {
        let speaker = settings["speaker"] as? String ?? "vivian"
        guard ["vivian", "serena", "uncle_fu", "dylan", "eric", "ryan", "aiden", "ono_anna", "sohee"].contains(speaker) else { throw fail("未知预设声音") }
        args += ["--speaker", speaker]
        if let voice = voice { args += ["--load-voice", voice.path]; args.append(voice.pathExtension == "bin" ? "--xvector-only" : "--icl-only") }
        if !instruction.isEmpty {
            guard spec.size == "1.7B" else { throw fail("0.6B 预设模型不支持官方风格指令，请切换到 1.7B 或清空指令。") }
            args += ["--instruct", instruction]
        }
    }
    // Optional research controls are deliberately allowlisted and never evaluated by a shell.
    if let advanced = settings["advanced"] as? [String: Any] {
        let numbers: [String: ClosedRange<Double>] = ["roughness": 0...1, "icl-frames": 0...1500, "greedy-warmup": 0...100, "onset-fade": 0...1, "compose-pause": 0...5, "voice-strength": 0...2, "max-duration": 1...600]
        for (key, value) in advanced.sorted(by: { $0.key < $1.key }) {
            if let range = numbers[key], let n = value as? NSNumber, n.doubleValue.isFinite, range.contains(n.doubleValue) { args += ["--" + key, n.stringValue] }
            else if ["tail-trim", "no-compose", "debug"].contains(key), let flag = value as? Bool { if flag { args.append("--" + key) } }
            else { throw fail("高级参数不受支持或超出范围：\(key)") }
        }
    }
    return args
}
