import SwiftUI

@main
struct AudioDoctorApp: App {
    @StateObject private var model = AppModel()

    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "batch"), args.indices.contains(index + 2) {
            let input = URL(fileURLWithPath: args[index + 1])
            let output = URL(fileURLWithPath: args[index + 2])
            let modeName = args.indices.contains(index + 3) ? args[index + 3].lowercased() : "analyze"
            let reference = args.indices.contains(index + 4) ? URL(fileURLWithPath: args[index + 4]) : nil
            do {
                var settings = BatchSettings()
                settings.mode = BatchMode(rawValue: modeName) ?? .analyze
                if settings.mode == .repair && reference != nil {
                    settings.repair.matchReference = true
                }
                let cancellation = BatchCancellation()
                let result = try BatchProcessor.run(
                    input: input,
                    output: output,
                    settings: settings,
                    referenceURL: reference,
                    progress: { progress in
                        FileHandle.standardOutput.write(Data((
                            String(format: "%d/%d success=%d failed=%d skipped=%d\r",
                                   progress.completed, progress.total, progress.succeeded, progress.failed, progress.skipped)
                        ).utf8))
                    },
                    cancellation: cancellation
                )
                FileHandle.standardOutput.write(Data((
                    "\nbatch complete: success=\(result.summary.succeeded) failed=\(result.summary.failed) skipped=\(result.summary.skipped) report=\(result.summary.reportURL?.path ?? "")\n"
                ).utf8))
                exit(result.summary.failed == 0 ? 0 : 1)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        if let index = args.firstIndex(of: "analyze"), args.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: args[index + 1])
            do {
                let loaded = try AudioIO.loadChannels(url: url)
                let report = AudioAnalyzer.analyze(channels: loaded.channels, sampleRate: loaded.sampleRate, filename: url.lastPathComponent)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        if let index = args.firstIndex(of: "repair"), args.indices.contains(index + 2) {
            let input = URL(fileURLWithPath: args[index + 1])
            let output = URL(fileURLWithPath: args[index + 2])
            let reference = args.indices.contains(index + 3) ? URL(fileURLWithPath: args[index + 3]) : nil
            do {
                let loaded = try AudioIO.loadChannels(url: input)
                let referenceChannels = reference == nil ? nil : try AudioIO.loadChannels(url: reference!).channels
                var options = RepairOptions()
                options.matchReference = reference != nil
                let repaired = AudioProcessor.repair(channels: loaded.channels, sampleRate: loaded.sampleRate, options: options, referenceChannels: referenceChannels)
                try AudioIO.write(channels: repaired, sampleRate: loaded.sampleRate, url: output, bitDepth: 24)
                FileHandle.standardOutput.write(Data(("repaired \(output.path)\n").utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
        if let index = args.firstIndex(of: "convert"), args.indices.contains(index + 3) {
            let input = URL(fileURLWithPath: args[index + 1])
            let output = URL(fileURLWithPath: args[index + 2])
            let target = args[index + 3]
            do {
                let loaded = try AudioIO.loadChannels(url: input)
                let converted = try AudioProcessor.convert(channels: loaded.channels, sampleRate: loaded.sampleRate, target: target)
                try AudioIO.write(channels: converted, sampleRate: loaded.sampleRate, url: output, bitDepth: 24)
                FileHandle.standardOutput.write(Data(("converted \(output.path) to \(converted.count) channels\n").utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1050, minHeight: 760)
        }
        .windowStyle(.automatic)
    }
}
