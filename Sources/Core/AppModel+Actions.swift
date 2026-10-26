import Foundation

extension AppModel {

    // MARK: - brew services 动作

    func perform(_ verb: ServiceVerb, on id: String) {
        Task { await performAsync(verb, id) }
    }

    func performAsync(_ verb: ServiceVerb, _ id: String) async {
        guard let current = item(id), !current.busy else { return }
        guard current.installed else {
            show(.info(L.t("%@ 还没安装，先安装再启动", current.title)))
            return
        }

        switch current.spec.kind {
        case .brew:
            await performBrew(verb, current)
        case .managed:
            await performManaged(verb, current)
        case .external:
            await performExternal(verb, current)
        }
    }

    // MARK: brew services

    private func performBrew(_ verb: ServiceVerb, _ current: ServiceItem) async {
        guard let brew = Shell.brewPath else {
            show(.error(L.t("未找到 Homebrew，请先安装 http://brew.sh")))
            return
        }
        setBusy(current.id, true, text: verb == .stop ? L.t("停止中…") : L.t("启动中…"))
        let result = await Shell.runAsync(brew, ["services", verb.rawValue, current.id], timeout: 240)
        setBusy(current.id, false)
        if result.ok {
            show(.success("\(current.title) \(verb.doneText)"))
        } else {
            let summary = Self.summarize(result.errorText)
            if let index = items.firstIndex(where: { $0.id == current.id }) {
                items[index].lastError = summary
            }
            show(.error(L.t("%@ %@：%@", current.title, verb.failureText, summary)))
        }
        await refresh(showSpinner: false)
    }

    // MARK: 启服托管（brew 只装了二进制、没有 service 的服务）

    private func performManaged(_ verb: ServiceVerb, _ current: ServiceItem) async {
        let spec = current.spec
        setBusy(current.id, true, text: verb == .stop ? L.t("停止中…") : L.t("启动中…"))
        var result = CommandResult()

        switch verb {
        case .start, .run:
            // 数据目录先备好
            for raw in spec.startArgs where raw.hasPrefix("~") {
                Paths.ensureDirectory((raw as NSString).expandingTildeInPath)
            }
            guard let plist = Launchctl.writeAgent(for: spec) else {
                setBusy(current.id, false)
                show(.error(L.t("%@ 无法写入 LaunchAgent（%@）", current.title, spec.managedPlistPath)))
                return
            }
            result = await Shell.runAsync("/bin/launchctl", ["bootstrap", Launchctl.userDomain, plist], timeout: 90)
            if !result.ok, result.status == 5 || result.errorText.contains("already") {
                result = await Shell.runAsync(
                    "/bin/launchctl",
                    ["kickstart", "-k", "\(Launchctl.userDomain)/\(spec.launchdLabel)"],
                    timeout: 60
                )
            }
            // 仅本次启动：加载成功后删掉 plist，重启不再自启
            if verb == .run, result.ok {
                Launchctl.removeAgent(for: spec)
            }
        case .stop:
            result = await Shell.runAsync(
                "/bin/launchctl",
                ["bootout", "\(Launchctl.userDomain)/\(spec.launchdLabel)"],
                timeout: 90
            )
            Launchctl.removeAgent(for: spec)
            if !result.ok, result.errorText.contains("No such process") {
                result = CommandResult()
            }
        case .restart:
            _ = await Shell.runAsync(
                "/bin/launchctl",
                ["bootout", "\(Launchctl.userDomain)/\(spec.launchdLabel)"],
                timeout: 90
            )
            for raw in spec.startArgs where raw.hasPrefix("~") {
                Paths.ensureDirectory((raw as NSString).expandingTildeInPath)
            }
            guard let plist = Launchctl.writeAgent(for: spec) else {
                setBusy(current.id, false)
                show(.error(L.t("%@ 无法写入 LaunchAgent", current.title)))
                return
            }
            result = await Shell.runAsync("/bin/launchctl", ["bootstrap", Launchctl.userDomain, plist], timeout: 90)
        }

        setBusy(current.id, false)
        report(result, item: current, verb: verb)
        await refresh(showSpinner: false)
    }

    // MARK: 系统守护进程（EasyTier 这类已注册在系统域的服务）

    private func performExternal(_ verb: ServiceVerb, _ current: ServiceItem) async {
        let spec = current.spec
        guard let plist = spec.daemonPlist else {
            show(.error(L.t("%@ 没有登记 plist 路径", current.title)))
            return
        }
        setBusy(current.id, true, text: verb == .stop ? L.t("等待管理员授权…") : L.t("启动中…"))

        let result: CommandResult
        switch verb {
        case .start, .run:
            // 已加载但进程没起来时，bootstrap 会报 already loaded，改用 kickstart
            if let state = TimerProbe.systemState(label: spec.launchdLabel), state.loaded {
                result = await Launchctl.kickstartSystemAsync(label: spec.launchdLabel)
            } else {
                result = await Launchctl.bootstrapSystemAsync(plist: plist)
            }
        case .stop:
            result = await Launchctl.bootoutSystemAsync(label: spec.launchdLabel)
        case .restart:
            result = await Launchctl.kickstartSystemAsync(label: spec.launchdLabel)
        }

        setBusy(current.id, false)
        if verb == .stop, !result.ok, result.errorText.contains("No such process") {
            show(.info(L.t("%@ 本来就没有加载", current.title)))
        } else {
            report(result, item: current, verb: verb)
        }
        await refresh(showSpinner: false)
    }

    private func report(_ result: CommandResult, item: ServiceItem, verb: ServiceVerb) {
        if result.ok {
            show(.success("\(item.title) \(verb.doneText)"))
        } else {
            let summary = Self.summarize(result.errorText)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].lastError = summary
            }
            show(.error(L.t("%@ %@：%@", item.title, verb.failureText, summary)))
        }
    }

    func installService(_ id: String) async {
        let spec = ServiceSpec.spec(for: id) ?? .fallback(id: id)
        let title = spec.title

        // 没有 brew 包的服务：直接给下载页
        if let url = spec.installURL, spec.installTarget == nil {
            if let target = URL(string: url) {
                openURL(target)
                show(.info(L.t("%@ 需要从官网下载安装，已打开下载页", title)))
            }
            return
        }

        guard let brew = Shell.brewPath else { return }
        let target = spec.installTarget ?? id
        setBusy(id, true, text: L.t("安装中…"))
        var result = await Shell.runAsync(brew, ["install", target], timeout: 2400)

        // Homebrew 7 会拒绝不受信任的 tap，先信任再重试一次
        if !result.ok, let tap = Self.untrustedTap(in: result.errorText) {
            setBusy(id, true, text: L.t("信任 tap…"))
            let trust = await Shell.runAsync(brew, ["trust", tap], timeout: 120)
            if trust.ok {
                show(.info(L.t("已信任 tap %@，正在重试安装 %@", tap, title)))
                setBusy(id, true, text: L.t("安装中…"))
                result = await Shell.runAsync(brew, ["install", target], timeout: 2400)
            }
        }

        setBusy(id, false)
        BrewCache.shared.invalidate()
        if result.ok {
            show(.success(L.t("%@ 安装完成", title)))
        } else {
            show(.error(L.t("%@ 安装失败：%@", title, Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false)
    }

    /// 从 brew 报错里取出不受信任的 tap 名
    nonisolated static func untrustedTap(in text: String) -> String? {
        guard let range = text.range(of: "untrusted tap ") else { return nil }
        let rest = text[range.upperBound...]
        guard let token = rest.split(whereSeparator: { $0 == " " || $0 == "\n" }).first else { return nil }
        let tap = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:'\""))
        return tap.isEmpty ? nil : tap
    }

    private func setBusy(_ id: String, _ busy: Bool, text: String = "") {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].busy = busy
        items[index].busyText = text
        if busy { items[index].lastError = nil }
    }

    /// 从命令输出里挑一句最有信息量的话
    nonisolated static func summarize(_ text: String, limit: Int = 180) -> String {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let error = lines.last { $0.hasPrefix("Error") || $0.contains("error:") || $0.contains("failed") }
        let picked = error ?? lines.last ?? L.t("未知错误")
        if picked.count <= limit { return picked }
        return String(picked.prefix(limit)) + "…"
    }

    // MARK: - Bun

    func upgradeBun() async {
        guard bun.installed, runtimeBusy == nil else { return }
        runtimeBusy = L.t("正在升级 Bun…")
        let result = await Shell.runAsync(bun.path, ["upgrade"], timeout: 900)
        runtimeBusy = nil
        if result.ok {
            show(.success(L.t("Bun 已升级到最新版")))
        } else {
            show(.error(L.t("Bun 升级失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    func installBun() async {
        guard runtimeBusy == nil else { return }
        runtimeBusy = L.t("正在安装 Bun…")
        let script = "curl -fsSL https://bun.sh/install | bash"
        let result = await Shell.runAsync("/bin/bash", ["-lc", script], timeout: 900)
        runtimeBusy = nil
        if result.ok {
            show(.success(L.t("Bun 安装完成")))
        } else {
            show(.error(L.t("Bun 安装失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    // MARK: - fnm / Node

    func setDefaultNode(_ version: String) async {
        guard let fnm = nodeFnmPath(), runtimeBusy == nil else { return }
        runtimeBusy = L.t("正在切换默认版本…")
        let result = await Shell.runAsync(fnm, ["default", version], timeout: 120)
        runtimeBusy = nil
        if result.ok {
            show(.success(L.t("Node 默认版本切换为 %@", version)))
        } else {
            show(.error(L.t("切换失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    func installNode(_ spec: String) async {
        guard let fnm = nodeFnmPath(), runtimeBusy == nil else { return }
        let target = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        runtimeBusy = L.t("正在安装 Node %@…", target)
        let result = await Shell.runAsync(fnm, ["install", target], timeout: 1800)
        runtimeBusy = nil
        if result.ok {
            show(.success(L.t("Node %@ 安装完成", target)))
        } else {
            show(.error(L.t("安装失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    func uninstallNode(_ version: String) async {
        guard let fnm = nodeFnmPath(), runtimeBusy == nil else { return }
        runtimeBusy = L.t("正在卸载 %@…", version)
        let result = await Shell.runAsync(fnm, ["uninstall", version], timeout: 300)
        runtimeBusy = nil
        if result.ok {
            show(.success(L.t("已卸载 Node %@", version)))
        } else {
            show(.error(L.t("卸载失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    func installFnm() async {
        guard let brew = Shell.brewPath, runtimeBusy == nil else { return }
        runtimeBusy = L.t("正在安装 fnm…")
        let result = await Shell.runAsync(brew, ["install", "fnm"], timeout: 1200)
        runtimeBusy = nil
        BrewCache.shared.invalidate()
        if result.ok {
            show(.success(L.t("fnm 安装完成")))
        } else {
            show(.error(L.t("fnm 安装失败：%@", Self.summarize(result.errorText))))
        }
        await refresh(showSpinner: false, runtimes: true)
    }

    private func nodeFnmPath() -> String? {
        let path = node.fnmPath.isEmpty ? (Shell.which("fnm") ?? "") : node.fnmPath
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            show(.error(L.t("未找到 fnm")))
            return nil
        }
        return path
    }
}
