import Foundation

/// 面向脚本与 AI 的命令行接口：`ServDock <command> [args] [--json]`
///
/// 给 AI 用的几条硬约定：
/// 1. **所有查询都支持 `--json`**，统一信封 `{ok, schema, tool, version, command, data}`
/// 2. **字段名稳定**：小写下划线，状态用枚举字面量（`started` / `stopped` / `running`…），不放中文
/// 3. **退出码**：`0` 成功 / `1` 执行失败 / `2` 用法错误
/// 4. `help --json` 输出机器可读的命令清单，工具可以自发现
/// 5. 动作类命令执行完会回读真实状态，不只报「已发送」
@MainActor
enum CLIRunner {
    /// JSON 信封版本，字段有破坏性变化时递增
    static let schemaVersion = 1

    // MARK: - 入口

    static func run(_ argv: [String]) {
        var args = argv
        if let index = args.firstIndex(of: "--lang"), index + 1 < args.count,
           let lang = Lang(rawValue: args[index + 1]) {
            L10n.setLanguage(lang)
            args.removeSubrange(index...(index + 1))
        }
        let json = args.contains("--json")
        let clean = args.filter { $0 != "--json" }

        guard let command = clean.first else {
            printUsage(json: json)
            exit(json ? 0 : 2)
        }
        let rest = Array(clean.dropFirst())

        switch command {
        case "version":
            emit("version",
                 ["name": Brand.name, "display_name": Brand.cjkName,
                  "version": Brand.version, "schema": schemaVersion,
                  "bundle_id": Brand.bundleID],
                 json: json,
                 human: "\(Brand.name) \(Brand.version)  ·  \(Brand.cjkName)  ·  schema \(schemaVersion)")

        case "help", "--help", "-h":
            printUsage(json: json)
            exit(0)

        case "list", "ls":
            listServices(rest, json: json)

        case "status":
            serviceStatus(rest, json: json)

        case "start", "stop", "restart", "run":
            serviceAction(command, rest, json: json)

        case "logs":
            serviceLogs(rest, json: json)

        case "containers", "ps":
            containers(rest, json: json)

        case "container":
            containerAction(rest, json: json)

        case "images":
            images(rest, json: json)

        case "docker-status", "engine":
            engineStatus(json: json)

        case "timers":
            timers(rest, json: json)

        case "timer":
            timerAction(rest, json: json)

        case "runtime":
            runtime(json: json)

        case "doctor":
            doctor(json: json)

        case "update", "check-update":
            updateCheck(json: json)

        default:
            fail("bad_usage", "未知命令：\(command)（执行 help 查看可用命令）", json: json, exitCode: 2)
        }
    }

    // MARK: - 服务

    private static func listServices(_ args: [String], json: Bool) {
        let onlyInstalled = args.contains("--installed")
        let onlyRunning = args.contains("--running")
        let category = value(of: "--category", in: args)

        var items = loadItems()
        if onlyInstalled { items = items.filter { $0.installed } }
        if onlyRunning { items = items.filter { $0.isRunning } }
        if let category {
            items = items.filter { $0.spec.category.rawValue == category }
        }

        if json {
            emit("list",
                 ["count": items.count,
                  "running_count": items.filter { $0.isRunning }.count,
                  "services": items.map(serviceDict)],
                 json: true, human: "")
        }

        guard !items.isEmpty else {
            print("没有匹配的服务")
            exit(0)
        }
        let header = pad("ID", 16) + pad("STATUS", 11) + pad("PID", 7) + pad("PORTS", 16)
            + pad("VERSION", 14) + "MANAGER"
        print(header)
        for item in items {
            let line = pad(item.id, 16)
                + pad(item.status.rawValue, 11)
                + pad(item.pid.map(String.init) ?? "-", 7)
                + pad(item.ports.isEmpty ? "-" : item.ports.map(String.init).joined(separator: ","), 16)
                + pad(item.version ?? "-", 14)
                + item.spec.kind.rawValue
            print(line)
        }
        print("\n\(items.count) 个服务，\(items.filter { $0.isRunning }.count) 个运行中")
        exit(0)
    }

    private static func serviceStatus(_ args: [String], json: Bool) {
        guard let id = positional(args) else {
            fail("bad_usage", "用法：status <service-id>", json: json, exitCode: 2)
        }
        guard let item = loadItems().first(where: { $0.id == id }) else {
            fail("not_found", "未知服务：\(id)（用 list 查看可用 id）", json: json)
        }
        if json {
            emit("status", serviceDict(item), json: true, human: "")
        }
        var lines = [
            "id        : \(item.id)",
            "name      : \(item.title)",
            "manager   : \(item.spec.kind.rawValue)",
            "category  : \(item.spec.category.rawValue)",
            "installed : \(item.installed)",
            "status    : \(item.status.rawValue)",
            "pid       : \(item.pid.map(String.init) ?? "-")",
            "ports     : \(item.ports.isEmpty ? "-" : item.ports.map(String.init).joined(separator: ","))",
            "version   : \(item.version ?? "-")"
        ]
        if let address = item.address { lines.append("address   : \(address)") }
        if let plist = item.plistPath { lines.append("plist     : \(plist)") }
        if let log = LogLocator.candidates(for: item).first?.path { lines.append("log       : \(log)") }
        if let error = item.lastError { lines.append("error     : \(error)") }
        print(lines.joined(separator: "\n"))
        exit(0)
    }

    private static func serviceAction(_ verbName: String, _ args: [String], json: Bool) {
        guard let id = positional(args), let verb = ServiceVerb(rawValue: verbName) else {
            fail("bad_usage", "用法：\(verbName) <service-id>", json: json, exitCode: 2)
        }
        Task { @MainActor in
            let model = AppModel(autoStart: false)
            await model.refresh(showSpinner: false, runtimes: false)
            guard let before = model.item(id) else {
                fail("not_found", "未知服务：\(id)", json: json)
            }
            guard before.installed else {
                fail("not_installed", "\(id) 未安装，先执行 brew install \(id)", json: json)
            }
            model.toast = nil
            let started = Date()
            await model.performAsync(verb, id)
            let elapsed = Int(Date().timeIntervalSince(started) * 1000)

            if let toast = model.toast, toast.kind == .error {
                fail("action_failed", toast.text, json: json)
            }
            guard let after = model.item(id) else {
                fail("action_failed", "动作执行后读不到服务状态", json: json)
            }
            var payload = serviceDict(after)
            payload["elapsed_ms"] = elapsed
            payload["previous_status"] = before.status.rawValue
            let human = "\(id): \(before.status.rawValue) -> \(after.status.rawValue)"
                + "  pid=\(after.pid.map(String.init) ?? "-")  \(elapsed)ms"
            emit(verbName, payload, json: json, human: human)
        }
        RunLoop.main.run()
    }

    private static func serviceLogs(_ args: [String], json: Bool) {
        guard let id = positional(args) else {
            fail("bad_usage", "用法：logs <service-id> [--lines N]", json: json, exitCode: 2)
        }
        let lines = Int(value(of: "--lines", in: args) ?? "200") ?? 200
        guard let item = loadItems().first(where: { $0.id == id }) else {
            fail("not_found", "未知服务：\(id)", json: json)
        }
        let candidates = LogLocator.candidates(for: item)
        guard let first = candidates.first else {
            fail("no_log", "\(id) 没有找到日志文件", json: json)
        }
        let text = trimLines(LogLocator.tail(first.path), limit: lines)
        if json {
            emit("logs",
                 ["id": id, "path": first.path, "requested_lines": lines,
                  "other_paths": candidates.dropFirst().map { $0.path },
                  "text": text],
                 json: true, human: "")
        }
        print(text)
        exit(0)
    }

    // MARK: - Docker

    private static func containers(_ args: [String], json: Bool) {
        let snap = DockerProbe.scan()
        guard snap.installed else {
            fail("cli_missing", "没有找到 docker 命令", json: json)
        }
        guard snap.daemonRunning else {
            fail("engine_down", snap.errorText ?? "容器引擎没有运行", json: json)
        }
        let onlyRunning = args.contains("--running")
        let list = onlyRunning ? snap.containers.filter { $0.isRunning } : snap.containers

        if json {
            emit("containers",
                 ["engine": snap.engine,
                  "server_version": snap.serverVersion,
                  "orb_status": snap.orbStatus,
                  "count": list.count,
                  "running_count": snap.runningCount,
                  "containers": list.map(containerDict)],
                 json: true, human: "")
        }
        guard !list.isEmpty else {
            print("没有容器")
            exit(0)
        }
        print(pad("NAME", 26) + pad("STATE", 10) + pad("PORTS", 22) + "IMAGE")
        for item in list {
            print(pad(item.name, 26) + pad(item.state, 10) + pad(item.shortPorts, 22) + item.image)
        }
        exit(0)
    }

    private static func containerAction(_ args: [String], json: Bool) {
        guard args.count >= 2 else {
            fail("bad_usage", "用法：container <start|stop|restart|rm|logs> <name> [--lines N]",
                 json: json, exitCode: 2)
        }
        let verb = args[0]
        let name = args[1]
        let lines = Int(value(of: "--lines", in: args) ?? "200") ?? 200

        Task { @MainActor in
            let snap = DockerProbe.scan()
            guard snap.daemonRunning else {
                fail("engine_down", snap.errorText ?? "容器引擎没有运行", json: json)
            }
            guard let target = snap.containers.first(where: { $0.name == name || $0.id.hasPrefix(name) }) else {
                fail("not_found", "没有这个容器：\(name)", json: json)
            }

            if verb == "logs" {
                let text = trimLines(DockerProbe.logs(target, lines: lines), limit: lines)
                if json {
                    emit("container-logs", ["name": target.name, "lines": lines, "text": text],
                         json: true, human: "")
                }
                print(text)
                exit(0)
            }

            let result: CommandResult
            switch verb {
            case "start": result = await DockerProbe.start(target)
            case "stop": result = await DockerProbe.stop(target)
            case "restart": result = await DockerProbe.restart(target)
            case "rm", "remove": result = await DockerProbe.remove(target)
            default:
                fail("bad_usage", "未知容器动作：\(verb)", json: json, exitCode: 2)
            }

            guard result.ok else {
                fail("action_failed", Summarize.error(result.errorText), json: json)
            }
            // 回读真实状态，别只报「已发送」
            let after = DockerProbe.scan().containers.first { $0.id == target.id || $0.name == target.name }
            let payload: [String: Any] = [
                "name": target.name,
                "verb": verb,
                "previous_state": target.state,
                "state": after?.state ?? NSNull(),
                "running": after?.isRunning ?? false
            ]
            emit("container", payload, json: json,
                 human: "\(target.name): \(target.state) -> \(after?.state ?? "unknown")")
        }
        RunLoop.main.run()
    }

    private static func images(_ args: [String], json: Bool) {
        let snap = DockerProbe.scan()
        guard snap.daemonRunning else {
            fail("engine_down", snap.errorText ?? "容器引擎没有运行", json: json)
        }
        if json {
            emit("images",
                 ["count": snap.images.count,
                  "disk_total": snap.diskTotal,
                  "reclaimable": snap.diskReclaimable,
                  "images": snap.images.map { image in
                      ["repository": image.repository, "tag": image.tag,
                       "size": image.size, "created": image.createdSince,
                       "id": image.shortID] as [String: Any]
                  }],
                 json: true, human: "")
        }
        guard !snap.images.isEmpty else {
            print("没有镜像")
            exit(0)
        }
        print(pad("IMAGE", 40) + pad("SIZE", 12) + pad("CREATED", 18) + "ID")
        for image in snap.images {
            print(pad(image.label, 40) + pad(image.size, 12) + pad(image.createdSince, 18) + image.shortID)
        }
        exit(0)
    }

    private static func engineStatus(json: Bool) {
        let snap = DockerProbe.scan()
        let payload: [String: Any] = [
            "cli": snap.cliPath ?? NSNull(),
            "installed": snap.installed,
            "engine": snap.engine,
            "server_version": snap.serverVersion,
            "daemon_running": snap.daemonRunning,
            "orb": snap.orbPath ?? NSNull(),
            "orb_status": snap.orbStatus,
            "containers": snap.containers.count,
            "running": snap.runningCount,
            "images": snap.images.count,
            "disk_total": snap.diskTotal,
            "error": snap.errorText ?? NSNull()
        ]
        emit("docker-status", payload, json: json,
             human: "engine=\(snap.engine.isEmpty ? "-" : snap.engine)  running=\(snap.daemonRunning)"
                + "  containers=\(snap.containers.count)(\(snap.runningCount))  images=\(snap.images.count)")
    }

    // MARK: - 定时任务

    private static func timers(_ args: [String], json: Bool) {
        let snap = TimerProbe.scan()
        let jobs = snap.jobs.map { job -> [String: Any] in
            ["label": job.label,
             "scope": job.scope.rawValue,
             "loaded": job.loaded,
             "pid": job.pid ?? NSNull(),
             "last_exit": job.lastExit ?? NSNull(),
             "schedule": job.schedule.text,
             "log": job.logPath ?? NSNull(),
             "is_servdock": job.isServDockAgent] as [String: Any]
        }
        if json {
            emit("timers",
                 ["count": jobs.count,
                  "cron_count": snap.cron.count,
                  "cron_readable": snap.cronReadable,
                  "jobs": jobs,
                  "cron": snap.cron.map { ["expression": $0.expression, "command": $0.command] }],
                 json: true, human: "")
        }
        guard !snap.jobs.isEmpty else {
            print("没有 launchd 任务")
            exit(0)
        }
        print(pad("SCOPE", 12) + pad("LOADED", 8) + pad("PID", 8) + pad("SCHEDULE", 26) + "LABEL")
        for job in snap.jobs {
            print(pad(job.scope.rawValue, 12)
                  + pad(job.loaded ? "yes" : "no", 8)
                  + pad(job.pid.map(String.init) ?? "-", 8)
                  + pad(job.schedule.text, 26)
                  + job.label)
        }
        exit(0)
    }

    private static func timerAction(_ args: [String], json: Bool) {
        guard args.count >= 2, let action = TimerJobAction(rawValue: args[0]) else {
            fail("bad_usage", "用法：timer <run|load|unload|enable|disable> <label>",
                 json: json, exitCode: 2)
        }
        let label = args[1]
        Task { @MainActor in
            let model = AppModel(autoStart: false)
            await model.loadTimers()
            guard let job = model.timers.jobs.first(where: { $0.label == label }) else {
                fail("not_found", "没有这个定时任务：\(label)", json: json)
            }
            model.toast = nil
            await model.performTimer(action, job: job)
            if let toast = model.toast, toast.kind == .error {
                fail("action_failed", toast.text, json: json)
            }
            let payload: [String: Any] = [
                "label": label,
                "action": action.rawValue,
                "message": model.toast?.text ?? "ok"
            ]
            emit("timer", payload, json: json,
                 human: "\(label): \(action.rawValue) -> \(model.toast?.text ?? "ok")")
        }
        RunLoop.main.run()
    }

    // MARK: - 运行时 / 诊断

    private static func runtime(json: Bool) {
        let snap = AppModel.collectSync(runtimes: true)
        let mise = MiseProbe.scan()
        let payload: [String: Any] = [
            "bun": ["installed": snap.bun.installed,
                    "version": snap.bun.version,
                    "path": snap.bun.path,
                    "shell_configured": snap.bun.shellConfigured,
                    "global_tools": snap.bun.binTools.count],
            "node": ["fnm_version": snap.node.fnmVersion,
                     "default": snap.node.defaultVersion ?? NSNull(),
                     "versions": snap.node.versions.map { $0.version },
                     "shell_configured": snap.node.shellConfigured],
            "mise": ["installed": mise.installed,
                     "version": mise.version,
                     "tools": mise.toolNames,
                     "activated": mise.activated,
                     "activated_shells": mise.activatedShells,
                     "login_shell": mise.loginShell,
                     "update_available": mise.updateAvailable]
        ]
        emit("runtime", payload, json: json,
             human: "bun=\(snap.bun.installed ? snap.bun.version : "-")"
                + "  node=\(snap.node.defaultVersion ?? "-")"
                + "  mise=\(mise.version.isEmpty ? "-" : mise.version)(\(mise.toolNames.count) tools)")
    }

    private static func doctor(json: Bool) {
        let items = loadItems()
        let mise = MiseProbe.scan()
        let docker = DockerProbe.scan()
        let timers = TimerProbe.scan()
        let easyTier = EasyTierProbe.scan()

        let brewPathJSON: Any = Shell.brewPath.map { $0 as Any } ?? NSNull()
        let payload: [String: Any] = [
            "app": ["name": Brand.name, "version": Brand.version, "schema": schemaVersion,
                    "support_dir": Brand.supportDir, "log_dir": Brand.logDir],
            "brew": ["path": brewPathJSON,
                     "version": SystemProbe.brewHomebrewVersion(),
                     "installed_services": items.filter { $0.installed }.count],
            "docker": ["installed": docker.installed,
                       "daemon_running": docker.daemonRunning,
                       "engine": docker.engine,
                       "containers": docker.containers.count,
                       "images": docker.images.count],
            "mise": ["installed": mise.installed, "version": mise.version,
                     "activated": mise.activated, "tools": mise.toolNames.count],
            "easytier": ["cli": easyTier.cliPath ?? NSNull(),
                         "rpc": easyTier.rpcPortal,
                         "reachable": easyTier.reachable,
                         "peers": easyTier.peers.count],
            "timers": ["launchd": timers.jobs.count, "cron": timers.cron.count],
            "services": ["total": items.count,
                         "installed": items.filter { $0.installed }.count,
                         "running": items.filter { $0.isRunning }.count]
        ]

        if json {
            emit("doctor", payload, json: true, human: "")
        }
        let lines = [
            "\(Brand.name) \(Brand.version)  (schema \(schemaVersion))",
            "数据目录 : \(Brand.supportDir)",
            "Homebrew : \(Shell.brewPath ?? "未安装") \(SystemProbe.brewHomebrewVersion())",
            "Docker   : \(docker.installed ? (docker.daemonRunning ? "运行中 (\(docker.engine))" : "已安装，引擎未运行") : "未安装")",
            "mise     : \(mise.installed ? "\(mise.version)  激活=\(mise.activated)" : "未安装")",
            "EasyTier : \(easyTier.reachable ? "已连接 \(easyTier.peers.count) 个节点" : (easyTier.cliPath == nil ? "未安装 CLI" : "RPC 不可达"))",
            "定时任务 : launchd \(timers.jobs.count) 个 / cron \(timers.cron.count) 个",
            "服务     : \(items.count) 个，已装 \(items.filter { $0.installed }.count)，运行 \(items.filter { $0.isRunning }.count)"
        ]
        print(lines.joined(separator: "\n"))
        exit(0)
    }

    // MARK: - 版本更新

    /// 只查询、不安装：脚本和 AI 拿到版本差异与下载地址后自己决定怎么做
    private static func updateCheck(json: Bool) {
        let snapshot = UpdateProbe.fetchLatest()
        let assetPayload: Any
        if let asset = snapshot.asset {
            assetPayload = ["name": asset.name, "url": asset.url, "size": asset.size]
        } else {
            assetPayload = NSNull()
        }
        let payload: [String: Any] = [
            "current": snapshot.current,
            "latest": snapshot.latest.isEmpty ? NSNull() : snapshot.latest,
            "state": snapshot.state.rawValue,
            "update_available": snapshot.hasUpdate,
            "release_name": snapshot.releaseName,
            "published_at": snapshot.publishedAt.isEmpty ? NSNull() : snapshot.publishedAt,
            "page_url": snapshot.pageURL.isEmpty ? Brand.releasesPage : snapshot.pageURL,
            "asset": assetPayload,
            "can_self_install": snapshot.canSelfInstall,
            "skipped": UpdateProbe.skippedVersion == snapshot.latest,
            "error": snapshot.error ?? NSNull()
        ]

        let human: String
        switch snapshot.state {
        case .available:
            human = "\(snapshot.current) -> \(snapshot.latest)"
                + "  可更新" + (snapshot.asset.map { "（\($0.name) \($0.sizeText)）" } ?? "")
                + (snapshot.canSelfInstall ? "" : "  仅手动安装")
        case .upToDate:
            human = "已是最新版本 \(snapshot.current)"
        case .failed:
            human = "检查更新失败：\(snapshot.error ?? "unknown")"
        case .idle:
            human = "未检查"
        }
        emit("update", payload, json: json, human: human)
    }

    // MARK: - 帮助

    private static func printUsage(json: Bool) {
        let commands: [[String: Any]] = [
            ["name": "version", "usage": "version", "desc": "版本与 JSON schema 版本"],
            ["name": "list", "usage": "list [--installed] [--running] [--category <cat>] [--json]",
             "desc": "所有服务及状态"],
            ["name": "status", "usage": "status <id> [--json]", "desc": "单个服务详情"],
            ["name": "start", "usage": "start <id> [--json]", "desc": "启动并设置开机自启"],
            ["name": "stop", "usage": "stop <id> [--json]", "desc": "停止"],
            ["name": "restart", "usage": "restart <id> [--json]", "desc": "重启"],
            ["name": "run", "usage": "run <id> [--json]", "desc": "仅本次启动（不设自启）"],
            ["name": "logs", "usage": "logs <id> [--lines N] [--json]", "desc": "服务日志尾部"],
            ["name": "containers", "usage": "containers [--running] [--json]", "desc": "Docker 容器列表"],
            ["name": "container", "usage": "container <start|stop|restart|rm|logs> <name> [--lines N] [--json]",
             "desc": "Docker 容器操作"],
            ["name": "images", "usage": "images [--json]", "desc": "Docker 镜像列表"],
            ["name": "docker-status", "usage": "docker-status [--json]", "desc": "容器引擎与 OrbStack 状态"],
            ["name": "timers", "usage": "timers [--json]", "desc": "launchd / cron 任务列表"],
            ["name": "timer", "usage": "timer <run|load|unload|enable|disable> <label> [--json]",
             "desc": "定时任务操作"],
            ["name": "runtime", "usage": "runtime [--json]", "desc": "bun / node / mise 运行时概览"],
            ["name": "doctor", "usage": "doctor [--json]", "desc": "环境体检（brew / docker / mise / EasyTier / 定时任务）"],
            ["name": "update", "usage": "update [--json]", "desc": "检查 GitHub Release 是否有新版本"]
        ]

        if json {
            emit("help",
                 ["commands": commands,
                  "envelope": ["ok": "Bool", "schema": "Int", "tool": "String",
                               "version": "String", "command": "String", "data": "Object",
                               "error": ["code": "String", "message": "String"]],
                  "exit_codes": ["0": "success", "1": "failed", "2": "bad usage"],
                  "service_status_values": BrewStatus.allCases.map { $0.rawValue }],
                 json: true, human: "")
        }

        print("\(Brand.name) \(Brand.version) — \(Brand.tagline)")
        print("")
        print("用法：\(Brand.name) <command> [args] [--json]")
        print("")

        let sections: [(String, [(String, String)])] = [
            ("服务", [
                ("list [--installed] [--running] [--category <cat>]", "列出服务（默认全部）"),
                ("status <id>", "单个服务详情"),
                ("start|stop|restart|run <id>", "启停；run 只启动不设自启"),
                ("logs <id> [--lines 200]", "看日志尾部"),
            ]),
            ("容器（Docker / OrbStack）", [
                ("containers [--running]", "容器列表（默认含已停止）"),
                ("container start|stop|restart|rm|logs <name>", "容器操作"),
                ("images", "镜像列表"),
                ("docker-status", "引擎与 OrbStack 状态"),
            ]),
            ("定时任务", [
                ("timers", "launchd / cron 列表"),
                ("timer run|load|unload|enable|disable <label>", "任务操作"),
            ]),
            ("运行时 / 诊断", [
                ("runtime", "bun / node / mise 概览"),
                ("doctor", "环境体检"),
                ("update", "检查新版本（只查询，不安装）"),
            ]),
            ("全局", [
                ("--json", "输出机器可读 JSON（信封：ok / schema / command / data）"),
                ("--lang en", "英文输出"),
                ("help [--json]", "本帮助；带 --json 时输出命令清单供程序解析"),
            ]),
        ]

        for (title, rows) in sections {
            print(title)
            for (command, desc) in rows {
                print("  " + pad(command, 52) + desc)
            }
            print("")
        }
        print("退出码：0 成功 / 1 执行失败 / 2 用法错误")
    }

    // MARK: - 工具

    private static func loadItems() -> [ServiceItem] {
        let model = AppModel(autoStart: false)
        model.refreshSync(runtimes: false)
        return model.items
    }

    private static func serviceDict(_ item: ServiceItem) -> [String: Any] {
        var dict: [String: Any] = [
            "id": item.id,
            "name": item.title,
            "category": item.spec.category.rawValue,
            "manager": item.spec.kind.rawValue,
            "installed": item.installed,
            "status": item.status.rawValue,
            "running": item.isRunning,
            "ports": item.ports,
            "address": item.address ?? NSNull(),
            "version": item.version ?? NSNull(),
            "pid": item.pid ?? NSNull(),
            "exit_code": item.exitCode ?? NSNull(),
            "plist": item.plistPath ?? NSNull(),
            "port_conflict": item.portConflict ?? NSNull(),
            "last_error": item.lastError ?? NSNull()
        ]
        if let path = LogLocator.candidates(for: item).first?.path {
            dict["log_path"] = path
        }
        return dict
    }

    private static func containerDict(_ item: DockerContainer) -> [String: Any] {
        [
            "name": item.name,
            "id": item.shortID,
            "full_id": item.id,
            "image": item.image,
            "state": item.state,
            "status": item.status,
            "running": item.isRunning,
            "ports": item.ports,
            "running_for": item.runningFor,
            "networks": item.networks
        ]
    }

    private static func emit(_ command: String, _ data: Any, json: Bool, human: String) -> Never {
        if json {
            let envelope: [String: Any] = [
                "ok": true,
                "schema": schemaVersion,
                "tool": Brand.name,
                "version": Brand.version,
                "command": command,
                "data": data
            ]
            print(encode(envelope))
        } else {
            print(human)
        }
        exit(0)
    }

    private static func fail(_ code: String, _ message: String, json: Bool, exitCode: Int32 = 1) -> Never {
        if json {
            let envelope: [String: Any] = [
                "ok": false,
                "schema": schemaVersion,
                "tool": Brand.name,
                "version": Brand.version,
                "error": ["code": code, "message": message]
            ]
            print(encode(envelope))
        } else {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        exit(exitCode)
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"encode_failed\",\"message\":\"JSON 编码失败\"}}"
        }
        return text
    }

    /// 取第一个不以 `--` 开头的参数
    private static func positional(_ args: [String]) -> String? {
        args.first { !$0.hasPrefix("--") }
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        // 中文按两格算，保证终端里对齐
        var visual = 0
        for scalar in text.unicodeScalars {
            visual += scalar.value > 0x2E80 ? 2 : 1
        }
        let padding = max(0, width - visual)
        return text + String(repeating: " ", count: padding)
    }

    private static func trimLines(_ text: String, limit: Int) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > limit else { return text }
        return lines.suffix(limit).joined(separator: "\n")
    }
}
