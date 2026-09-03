import Foundation
let args = CommandLine.arguments
if args.count != 4 { print("Usage: download-test model-id source absolute-output-dir"); exit(2) }
let control = OperationControl(); control.begin()
do {
    try downloadModelFiles(ModelSpec.find(args[1]), source: args[2], folder: URL(fileURLWithPath: args[3]), control: control, log: { print($0, terminator: ""); fflush(stdout) }, progress: { _, _ in })
    print("VERIFIED COMPLETE MODEL")
} catch { print("ERROR: \(error.localizedDescription)"); exit(1) }
