import Foundation

final class CodexAppServerClient: @unchecked Sendable {
    private typealias ResponseCompletion = @Sendable (Result<[String: Any], Error>) -> Void

    private let codexPath = "/Applications/Codex.app/Contents/Resources/codex"
    private let queue = DispatchQueue(label: "CodexAppServerClient")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutBuffer = Data()
    private var nextId = 1
    private var initialized = false
    private var pending: [Int: ResponseCompletion] = [:]

    deinit {
        process?.terminate()
    }

    func readRateLimits(completion: @escaping @Sendable (Result<QuotaSnapshot, Error>) -> Void) {
        queue.async {
            do {
                try self.ensureStarted()
                self.initializeIfNeeded {
                    switch $0 {
                    case .success:
                        self.send(method: "account/rateLimits/read", params: nil) { result in
                            completion(result.flatMap(Self.parseRateLimits))
                        }
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private func ensureStarted() throws {
        if let process, process.isRunning {
            return
        }

        guard FileManager.default.isExecutableFile(atPath: codexPath) else {
            throw QuotaError.codexBinaryMissing(codexPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let client = self else { return }
            client.queue.async {
                client.consumeStdout(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] _ in
            guard let client = self else { return }
            client.queue.async {
                client.failAll(QuotaError.processNotRunning)
                client.initialized = false
            }
        }

        try process.run()
        self.process = process
        self.stdinPipe = stdinPipe
    }

    private func initializeIfNeeded(completion: @escaping ResponseCompletion) {
        if initialized {
            completion(.success([:]))
            return
        }

        let params: [String: Any] = [
            "clientInfo": [
                "name": "codex-quota",
                "title": "Codex Quota",
                "version": "0.1.0"
            ],
            "capabilities": [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": []
            ]
        ]

        send(method: "initialize", params: params) { result in
            if case .success = result {
                self.queue.async {
                    self.initialized = true
                }
            }
            completion(result)
        }
    }

    private func send(
        method: String,
        params: [String: Any]?,
        completion: @escaping ResponseCompletion
    ) {
        guard let process, process.isRunning, let stdinPipe else {
            completion(.failure(QuotaError.processNotRunning))
            return
        }

        let id = nextId
        nextId += 1
        pending[id] = completion

        var message: [String: Any] = [
            "id": id,
            "method": method
        ]
        if let params {
            message["params"] = params
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            stdinPipe.fileHandleForWriting.write(data)
            stdinPipe.fileHandleForWriting.write(Data([0x0A]))
        } catch {
            pending.removeValue(forKey: id)
            completion(.failure(error))
        }
    }

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any],
            let id = message["id"] as? Int,
            let completion = pending.removeValue(forKey: id)
        else {
            return
        }

        if let result = message["result"] as? [String: Any] {
            completion(.success(result))
        } else if let error = message["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown app-server error"
            completion(.failure(QuotaError.serverError(message)))
        } else {
            completion(.failure(QuotaError.invalidResponse))
        }
    }

    private func failAll(_ error: Error) {
        let completions = pending.values
        pending.removeAll()
        for completion in completions {
            completion(.failure(error))
        }
    }

    private static func parseRateLimits(_ response: [String: Any]) -> Result<QuotaSnapshot, Error> {
        let codexLimits: [String: Any]?
        let sparkLimits: [String: Any]?

        if
            let byId = response["rateLimitsByLimitId"] as? [String: Any],
            let codex = byId["codex"] as? [String: Any]
        {
            codexLimits = codex
            sparkLimits = findSparkLimits(in: byId)
        } else {
            codexLimits = response["rateLimits"] as? [String: Any]
            sparkLimits = nil
        }

        guard
            let limits = codexLimits,
            let codexBucket = parseBucket("Codex 限额", limits)
        else {
            return .failure(QuotaError.missingRateLimits)
        }

        let sparkBucket = sparkLimits.flatMap { parseBucket("GPT-5.3-Codex-Spark 限额", $0) }
        return .success(QuotaSnapshot(codex: codexBucket, spark: sparkBucket, fetchedAt: Date()))
    }

    private static func findSparkLimits(in byId: [String: Any]) -> [String: Any]? {
        if let direct = byId["codex_bengalfox"] as? [String: Any] {
            return direct
        }

        for (_, value) in byId {
            guard let bucket = value as? [String: Any] else {
                continue
            }
            let id = (bucket["limitId"] as? String)?.lowercased() ?? ""
            let name = (bucket["limitName"] as? String)?.lowercased() ?? ""
            if id != "codex", name.contains("spark") {
                return bucket
            }
        }

        return nil
    }

    private static func parseBucket(_ title: String, _ limits: [String: Any]) -> QuotaBucket? {
        guard
            let primary = limits["primary"] as? [String: Any],
            let secondary = limits["secondary"] as? [String: Any],
            let fiveHour = parseWindow("5小时", primary),
            let weekly = parseWindow("周限额", secondary)
        else {
            return nil
        }

        return QuotaBucket(title: title, fiveHour: fiveHour, weekly: weekly)
    }

    private static func parseWindow(_ title: String, _ value: [String: Any]) -> QuotaWindow? {
        guard let usedPercent = value["usedPercent"] as? Int else {
            return nil
        }

        let resetAt: Date?
        if let seconds = value["resetsAt"] as? TimeInterval {
            resetAt = Date(timeIntervalSince1970: seconds)
        } else {
            resetAt = nil
        }

        return QuotaWindow(title: title, usedPercent: usedPercent, resetAt: resetAt)
    }
}
