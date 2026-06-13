import Foundation

/// 通过 stdio JSON-RPC 与本机 Codex app-server 通信的客户端。
///
/// 该类型内部使用串行队列保护进程、请求 ID、待完成回调与 stdout 缓冲区。
final class CodexAppServerClient: @unchecked Sendable {
    /// JSON-RPC 响应完成回调。
    ///
    /// - Parameter Result: 成功时为响应对象字典，失败时为启动、通信或服务端错误。
    private typealias ResponseCompletion = @Sendable (Result<[String: Any], Error>) -> Void

    /// Codex.app 内置命令行程序路径。
    private let codexPath = "/Applications/Codex.app/Contents/Resources/codex"
    /// 串行化所有进程与协议状态访问的队列。
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

    /// 读取当前账号的 Codex 额度。
    ///
    /// - Parameter completion: 异步完成回调；成功时返回 `QuotaSnapshot`，失败时返回 `QuotaError` 或系统错误。
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

    /// 确保 app-server 进程已启动并连接到 stdio。
    ///
    /// - Throws: 当 Codex 二进制不存在、不可执行或进程启动失败时抛出错误。
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

    /// 首次请求前执行 app-server 初始化握手。
    ///
    /// - Parameter completion: 初始化完成回调；已经初始化时立即返回成功。
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

    /// 发送一条 JSON-RPC 请求到 app-server。
    ///
    /// - Parameters:
    ///   - method: JSON-RPC 方法名，例如 `initialize` 或 `account/rateLimits/read`。
    ///   - params: 请求参数字典；无参数时传 `nil`。
    ///   - completion: 与请求 ID 绑定的响应回调。
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

    /// 消费 stdout 字节流并按换行切分 JSON-RPC 消息。
    ///
    /// - Parameter data: app-server stdout 新读取到的数据块。
    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[..<newline]
            stdoutBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handleLine(Data(line))
        }
    }

    /// 解析并分发单行 JSON-RPC 响应。
    ///
    /// - Parameter data: 不包含换行符的 UTF-8 JSON 数据。
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

    /// 让所有待处理请求以同一个错误失败。
    ///
    /// - Parameter error: 要传给每个待完成回调的错误。
    private func failAll(_ error: Error) {
        let completions = pending.values
        pending.removeAll()
        for completion in completions {
            completion(.failure(error))
        }
    }

    /// 将 app-server 原始响应转换成 UI 使用的额度快照。
    ///
    /// - Parameter response: `account/rateLimits/read` 返回的 JSON 对象。
    /// - Returns: 成功时返回 `QuotaSnapshot`，缺少必要额度字段时返回失败。
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

    /// 从按 limitId 分组的响应中查找 Spark 额度。
    ///
    /// - Parameter byId: app-server 返回的 `rateLimitsByLimitId` 字典。
    /// - Returns: 找到的 Spark 限额对象；未返回 Spark 额度时为 `nil`。
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

    /// 将单个模型的原始额度对象解析为 `QuotaBucket`。
    ///
    /// - Parameters:
    ///   - title: UI 展示名称。
    ///   - limits: 包含 `primary` 与 `secondary` 的原始额度对象。
    /// - Returns: 解析成功的额度桶；缺少任一窗口时为 `nil`。
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

    /// 将单个窗口的原始额度对象解析为 `QuotaWindow`。
    ///
    /// - Parameters:
    ///   - title: UI 展示名称。
    ///   - value: 包含 `usedPercent` 与可选 `resetsAt` 的原始窗口对象。
    /// - Returns: 解析成功的限额窗口；缺少 `usedPercent` 时为 `nil`。
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
