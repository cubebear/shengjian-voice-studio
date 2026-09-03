import Foundation
import AVFoundation

var passed = 0, failed = 0
func check(_ name: String, _ body: () throws -> Bool) {
    do { if try body() { passed += 1; print("PASS: \(name)") } else { failed += 1; print("FAIL: \(name)") } }
    catch { failed += 1; print("FAIL: \(name): \(error)") }
}
func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/shengjian-tests-\(UUID().uuidString)")
try mkdir(dir)
let pcm = PCM(rate: 24000, samples: (0..<48000).map { Float(sin(Double($0) * 2 * .pi * 440 / 24000)) * 0.4 })
let wav = dir.appendingPathComponent("sine.wav")
try pcm.write(wav)
check("PCM16 WAV roundtrip duration and amplitude") {
    let read = try PCM.read(wav)
    return read.rate == 24000 && read.samples.count == 48000 && zip(read.samples, pcm.samples).allSatisfy { abs($0 - $1) < 0.00004 }
}
check("Trim, fade and normalization preserve bounded samples") {
    let edit = try pcm.edited(start: 0.5, end: 1.5, gain: 0, normalize: true, fade: 0.03)
    return edit.samples.count == 24000 && edit.samples[0] == 0 && edit.samples.last == 0 && abs((edit.samples.map { abs($0) }.max() ?? 0) - 0.95) < 0.001
}
check("Invalid crop rejected before write") { rejects { _ = try pcm.edited(start: 1.5, end: 1, gain: 0, normalize: false, fade: 0) } }
check("Join inserts exact silent interval") {
    let join = try PCM.join([pcm, pcm], gap: 0.25)
    return join.samples.count == 102000 && join.samples[48000..<54000].allSatisfy { $0 == 0 }
}
check("Mixed sample rates rejected") { rejects { _ = try PCM.join([pcm, PCM(rate: 16000, samples: [0])], gap: 0) } }
check("Offline speed/pitch rendering produces expected duration") {
    let target = dir.appendingPathComponent("speed-pitch.caf"), control = OperationControl(); control.begin()
    try timePitch(wav, target, rate: 1.25, pitch: 3, control: control)
    let result = try PCM.read(target)
    print("Audio rendered: \(result.duration)s, peak \(result.samples.map { abs($0) }.max() ?? 0), samples \(result.samples.count)")
    let body = Array(result.samples[4800..<result.samples.count - 4800])
    let crossings = (1..<body.count).filter { body[$0 - 1] <= 0 && body[$0] > 0 }.count
    let frequency = Double(crossings) / (Double(body.count) / 24000)
    print("Pitch frequency: \(frequency) Hz (expected ~523 Hz)")
    return abs(result.duration - 1.6) < 0.015 && abs(frequency - 523.25) < 20 && result.samples.contains { abs($0) > 0.05 }
}
check("Cancellation prevents starting subprocess") {
    let ctl = OperationControl(); ctl.begin(); ctl.cancel()
    return rejects { try runProcess(URL(fileURLWithPath: "/usr/bin/true"), [], control: ctl) }
}
check("Active subprocess cancellation terminates the owned process") {
    let ctl = OperationControl(); ctl.begin()
    let start = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { ctl.cancel() }
    return rejects { try runProcess(URL(fileURLWithPath: "/bin/sleep"), ["10"], control: ctl) } && ctl.isCancelled && Date().timeIntervalSince(start) < 3
}
check("Subprocess nonzero exit surfaced") { rejects { try runProcess(URL(fileURLWithPath: "/usr/bin/false"), []) } }
check("Unicode splitting preserves punctuation and graphemes") {
    let text = String(repeating: "你好👨‍👩‍👧‍👦！", count: 20), parts = splitText(text, limit: 30)
    return parts.joined() == text && parts.allSatisfy { $0.count <= 30 }
}
check("UTF-8, BOM UTF-16, GB18030 imported correctly") {
    let sample = "中文测试，你好！"
    let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    return try [sample.data(using: .utf8)!, sample.data(using: .utf16)!, sample.data(using: gb)!].allSatisfy { try decodeText($0) == sample }
}
let custom = try ModelSpec.find("custom-small"), base = try ModelSpec.find("base-small"), design = try ModelSpec.find("design")
func args(_ spec: ModelSpec, _ settings: [String: Any] = [:], voice: URL? = nil) throws -> [String] { try engineArguments(spec: spec, model: dir, text: "你好；$(touch /never-run)", output: wav, settings: settings, reference: nil, voice: voice) }
check("Model arguments keep text as one literal argument") {
    let result = try args(custom)
    return result[result.firstIndex(of: "--text")! + 1] == "你好；$(touch /never-run)" && result.contains("--int8")
}
check("Base rejects missing reference") { rejects { _ = try args(base) } }
check("VoiceDesign requires instruction") { rejects { _ = try args(design) } }
check("0.6B CustomVoice rejects unsupported instruction") { rejects { _ = try args(custom, ["instruction": "温柔"]) } }
check("Unknown advanced flags rejected") { rejects { _ = try args(custom, ["advanced": ["model-dir": "/tmp"]]) } }
check("Out of range numeric settings rejected") { rejects { _ = try args(custom, ["temperature": 100]) } }
let smallVoice = dir.appendingPathComponent("small.bin"), largeVoice = dir.appendingPathComponent("large.bin")
try Data(repeating: 0, count: 4096).write(to: smallVoice)
try Data(repeating: 0, count: 8192).write(to: largeVoice)
check("Voice size checked against model before execution") {
    _ = try args(base, voice: smallVoice)
    return rejects { _ = try args(base, voice: largeVoice) }
}
check("Truncated qvoice rejected") {
    let file = dir.appendingPathComponent("broken.qvoice"); try Data("QVCE".utf8).write(to: file)
    return rejects { _ = try validateVoice(file) }
}
check("Git LFS pointer rejected as model weights") {
    let file = dir.appendingPathComponent("pointer.safetensors")
    try Data("version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 1000\n".utf8).write(to: file)
    return rejects { try validateSafetensors(file) }
}
check("Safetensors payload bounds validated") {
    let file = dir.appendingPathComponent("bounds.safetensors")
    let header = try JSONSerialization.data(withJSONObject: ["weight": ["dtype": "BF16", "shape": [2], "data_offsets": [0, 1000]]])
    var bytes = Data((0..<8).map { UInt8((UInt64(header.count) >> ($0 * 8)) & 255) }); bytes.append(header); bytes.append(contentsOf: [0, 0, 0, 0]); try bytes.write(to: file)
    return rejects { try validateSafetensors(file) }
}
check("Incomplete model directory fails clearly") { rejects { _ = try validateModel(dir) } }
check("SHA256 file hashing stable") {
    let file = dir.appendingPathComponent("hash.txt"); try Data("abc".utf8).write(to: file)
    return try sha256(file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
}

check("ModelScope manifest uses pinned file revisions and SHA256") {
    let fixture = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("modelscope-base.json")
    let manifest = try DownloadManifest.parse(jsonRead(fixture), spec: base, source: "modelscope")
    return manifest.records.count == 11 && manifest.records.allSatisfy { $0.sha256?.count == 64 && $0.revision.count == 40 } && manifest.fileURL(manifest.records[0]).hasPrefix("https://modelscope.cn/api/v1/models/Qwen/")
}
check("Hugging Face manifest uses commit hashes, LFS SHA256 and git hashes") {
    let files: [[String: Any]] = ModelSpec.files.map { name in
        if name.hasSuffix("safetensors") { return ["rfilename": name, "size": 1000, "lfs": ["sha256": String(repeating: "a", count: 64)]] }
        return ["rfilename": name, "size": 100, "blobId": String(repeating: "b", count: 40)]
    }
    let manifest = try DownloadManifest.parse(["sha": String(repeating: "c", count: 40), "siblings": files], spec: base, source: "huggingface")
    return manifest.records.count == 11 && manifest.fileURL(manifest.records[0]).contains("/resolve/" + String(repeating: "c", count: 40) + "/")
}
check("Incomplete or untrusted download manifests rejected") {
    rejects { _ = try DownloadManifest.parse(["Success": true, "Data": ["Files": []]], spec: base, source: "modelscope") } && rejects { _ = try DownloadManifest.metadataURL(spec: base, source: "http://untrusted") }
}
print("\(passed) passed; \(failed) failed")
exit(failed == 0 ? 0 : 1)
