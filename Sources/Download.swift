import Foundation
import CryptoKit

struct DownloadRecord {
    let name: String, revision: String, size: Int64, sha256: String?, gitBlob: String?
}
struct DownloadManifest {
    let source: String, repo: String, records: [DownloadRecord]
    static func parse(_ json: [String: Any], spec: ModelSpec, source: String) throws -> DownloadManifest {
        guard ["modelscope", "huggingface"].contains(source) else { throw fail("请选择魔搭或 Hugging Face 下载源") }
        func validHex(_ text: String?, _ count: Int) -> Bool { text?.range(of: "^[0-9a-f]{\(count)}$", options: .regularExpression) != nil }
        let files: [[String: Any]], globalRevision: String?
        if source == "modelscope" {
            guard json["Success"] as? Bool == true, let data = json["Data"] as? [String: Any], let list = data["Files"] as? [[String: Any]] else { throw fail("魔搭返回了无效文件清单，请检查网络或重试。") }
            files = list; globalRevision = nil
        } else {
            guard let list = json["siblings"] as? [[String: Any]], let sha = json["sha"] as? String, validHex(sha, 40) else { throw fail("Hugging Face 返回了无效文件清单，请检查网络或切换魔搭。") }
            files = list; globalRevision = sha
        }
        let records = try ModelSpec.files.map { name -> DownloadRecord in
            let ms = source == "modelscope"
            guard let file = files.first(where: { $0[ms ? "Path" : "rfilename"] as? String == name }),
                  let bytes = file[ms ? "Size" : "size"] as? NSNumber, bytes.int64Value > 0, bytes.int64Value < 30_000_000_000 else { throw fail("下载清单缺少 \(name) 或大小异常。") }
            let revision = globalRevision ?? file["Revision"] as? String ?? ""
            let hash = ms ? file["Sha256"] as? String : (file["lfs"] as? [String: Any])?["sha256"] as? String
            let blob = ms ? nil : file["blobId"] as? String
            guard validHex(revision, 40), validHex(hash, 64) || (hash == nil && validHex(blob, 40) && bytes.int64Value < 64 * 1024 * 1024) else { throw fail("下载清单缺少有效版本或校验值：\(name)") }
            return DownloadRecord(name: name, revision: revision, size: bytes.int64Value, sha256: hash, gitBlob: blob)
        }
        return DownloadManifest(source: source, repo: spec.repo, records: records)
    }
    static func metadataURL(spec: ModelSpec, source: String) throws -> String {
        if source == "modelscope" { return "https://modelscope.cn/api/v1/models/\(spec.repo)/repo/files?Revision=master&Recursive=true" }
        if source == "huggingface" { return "https://huggingface.co/api/models/\(spec.repo)/revision/main?blobs=true" }
        throw fail("无效下载源")
    }
    func fileURL(_ record: DownloadRecord) -> String {
        if source == "modelscope" {
            var url = URLComponents(string: "https://modelscope.cn/api/v1/models/\(repo)/repo")!
            url.queryItems = [URLQueryItem(name: "Revision", value: record.revision), URLQueryItem(name: "FilePath", value: record.name)]
            return url.url!.absoluteString
        }
        return "https://huggingface.co/\(repo)/resolve/\(record.revision)/\(record.name)"
    }
    func verified(_ file: URL, record: DownloadRecord) throws -> Bool {
        guard fileSize(file) == record.size else { return false }
        if let hash = record.sha256 { return try sha256(file) == hash }
        guard let hash = record.gitBlob else { return false }
        var data = Data("blob \(record.size)\0".utf8); data.append(try Data(contentsOf: file))
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash
    }
}

func downloadModelFiles(_ spec: ModelSpec, source: String, folder: URL, control: OperationControl, log: @escaping (String) -> Void, progress: @escaping (String, Double) -> Void) throws {
    let metadataURL = try DownloadManifest.metadataURL(spec: spec, source: source)
    try mkdir(folder)
    let receipt = folder.appendingPathComponent("download-receipt-\(source).json")
    let metadata: [String: Any], manifest: DownloadManifest
    if let cached = try? jsonRead(receipt), let parsed = try? DownloadManifest.parse(cached, spec: spec, source: source) {
        metadata = cached; manifest = parsed
    } else {
        let temp = folder.appendingPathComponent("metadata-\(source).partial")
        try runProcess(URL(fileURLWithPath: "/usr/bin/curl"), ["--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--connect-timeout", "20", "--max-time", "90", "--output", temp.path, metadataURL], control: control, log: log)
        metadata = try jsonRead(temp)
        manifest = try DownloadManifest.parse(metadata, spec: spec, source: source)
        try jsonWrite(metadata, receipt); try? fm.removeItem(at: temp)
    }
    log("来源：\(source == "modelscope" ? "魔搭 ModelScope（中国大陆）" : "Hugging Face")\n版本已固定；按该来源公布的 SHA-256 / Git blob 哈希校验。不会静默切换来源。\n")
    let total = manifest.records.reduce(Int64(0)) { $0 + $1.size }
    let missing = manifest.records.reduce(Int64(0)) { $0 + max(0, $1.size - fileSize(folder.appendingPathComponent($1.name))) }
    let free = ((try? fm.attributesOfFileSystem(forPath: folder.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0
    guard free > missing + 1024 * 1024 * 1024 else { throw fail("磁盘空间不足，需要至少 \(ByteCountFormatter.string(fromByteCount: missing + 1024 * 1024 * 1024, countStyle: .file)) 空闲空间。") }
    var finished: Int64 = 0
    for record in manifest.records {
        try control.check()
        let destination = folder.appendingPathComponent(record.name)
        let partial = destination.appendingPathExtension("\(source).part")
        try mkdir(destination.deletingLastPathComponent())
        if try manifest.verified(destination, record: record) { log("校验通过，跳过 \(record.name)\n"); finished += record.size; continue }
        if try !manifest.verified(partial, record: record) {
            // A full-length corrupt partial cannot be resumed safely; start it again.
            if fileSize(partial) >= record.size { try fm.removeItem(at: partial) }
            progress("下载 \(record.name)", Double(finished) / Double(max(1, total)))
            var args = ["--fail", "--location", "--proto", "=https", "--proto-redir", "=https", "--tlsv1.2", "--connect-timeout", "30", "--speed-limit", "1024", "--speed-time", "120", "--retry", "3", "--continue-at", "-", "--output", partial.path, manifest.fileURL(record)]
            let output: (String) -> Void = { text in
                log(text)
                progress("\(record.name) · \(ByteCountFormatter.string(fromByteCount: fileSize(partial), countStyle: .file))", Double(finished + min(record.size, fileSize(partial))) / Double(max(1, total)))
            }
            do { try runProcess(URL(fileURLWithPath: "/usr/bin/curl"), args, control: control, log: output) }
            catch {
                if !control.isCancelled && error.localizedDescription.contains("进程退出（33）") {
                    log("服务器不支持断点，重新下载当前文件。\n")
                    try? fm.removeItem(at: partial)
                    if let index = args.firstIndex(of: "--continue-at") { args.removeSubrange(index...index + 1) }
                    try runProcess(URL(fileURLWithPath: "/usr/bin/curl"), args, control: control, log: output)
                } else { throw error }
            }
            guard try manifest.verified(partial, record: record) else { try? fm.removeItem(at: partial); throw fail("下载校验失败：\(record.name)。错误文件已丢弃，请重试；若仍失败，可从所选来源手动下载后导入。") }
        }
        if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: partial) }
        else { try fm.moveItem(at: partial, to: destination) }
        finished += record.size
    }
    _ = try validateModel(folder, expected: spec)
    progress("下载并校验完成", 1)
}
