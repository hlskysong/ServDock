import Foundation

// MARK: - EasyTier / Homebrew 包 / mise 的数据加载与动作

extension AppModel {

    // MARK: EasyTier

    func loadEasyTier() async {
        if etRefreshing { return }
        etRefreshing = true
        let snapshot = await Task.detached(priority: .userInitiated) {
            EasyTierProbe.scan()
        }.value
        easyTier = snapshot
        etRefreshing = false
    }

    func installEasyTierCLI() async {
        guard !etCliInstalling else { return }
        etCliInstalling = true
        let result = await Task.detached(priority: .userInitiated) {
            EasyTierProbe.installCLI()
        }.value
        etCliInstalling = false
        switch result {
        case .success(let path):
            show(.success(L.t("easytier-cli 已就绪：%@", path)))
            await loadEasyTier()
        case .failure(let message):
            show(.error(message))
        }
    }

    // MARK: Homebrew 包

    func loadInstalledPackages() async {
        if brewLoading { return }
        brewLoading = true
        let list = await Task.detached(priority: .userInitiated) {
            BrewCatalog.installedFormulae() + BrewCatalog.installedCasks()
        }.value
        brewInstalled = list
        brewLoading = false
        syncBrewInstalledFlags()
    }

    func reloadBrewPackages() async {
        await loadInstalledPackages()
        let keyword = brewLastQuery
        if !keyword.isEmpty {
            await searchBrewPackages(keyword)
        }
    }

    func searchBrewPackages(_ keyword: String) async {
        if brewSearching { return }
        brewSearching = true
        brewLastQuery = keyword
        let kind = brewKind
        let results = await Task.detached(priority: .userInitiated) {
            BrewCatalog.search(keyword, kind: kind)
        }.value
        brewResults = results
        brewSearching = false
        if brewInstalled.isEmpty {
            await loadInstalledPackages()
        } else {
            syncBrewInstalledFlags()
        }
    }

    /// 用已安装列表校准搜索结果的 installed 标记
    private func syncBrewInstalledFlags() {
        guard !brewInstalled.isEmpty, !brewResults.isEmpty else { return }
        let installedSet = Set(brewInstalled.filter { $0.kind == brewKind }.map { $0.name })
        for index in brewResults.indices where installedSet.contains(brewResults[index].name) {
            brewResults[index].installed = true
        }
    }

    func installPackage(_ pkg: BrewPackage) async {
        guard brewBusy == nil else { return }
        brewBusy = pkg.id
        let result = await BrewCatalog.install(pkg)
        brewBusy = nil
        if result.ok {
            show(.success(L.t("%@ 安装完成", pkg.name)))
        } else {
            let summary = Summarize.error(result.errorText)
            show(.error(L.t("%@ 安装失败：%@", pkg.name, summary)))
        }
        await loadInstalledPackages()
        if brewTab == .installed { await reloadBrewPackages() }
        await refresh(showSpinner: false)
    }

    func uninstallPackage(_ pkg: BrewPackage) async {
        guard brewBusy == nil else { return }
        brewBusy = pkg.id
        let result = await BrewCatalog.uninstall(pkg)
        brewBusy = nil
        if result.ok {
            show(.success(L.t("已卸载 %@", pkg.name)))
            brewResults.removeAll { $0.id == pkg.id }
        } else {
            show(.error(L.t("卸载失败：%@", Summarize.error(result.errorText))))
        }
        await loadInstalledPackages()
        await refresh(showSpinner: false)
    }

    // MARK: mise

    func loadMise() async {
        if miseLoading { return }
        miseLoading = true
        let snapshot = await Task.detached(priority: .userInitiated) {
            MiseProbe.scan()
        }.value
        mise = snapshot
        miseLoading = false
    }

    func searchMise(_ keyword: String) async {
        if miseSearching { return }
        miseSearching = true
        let results = await Task.detached(priority: .userInitiated) {
            MiseProbe.search(keyword)
        }.value
        miseSearchResults = results
        miseSearching = false
    }

    /// 把 `mise activate <shell>` 写进对应 shell 的配置文件（幂等）
    func writeMiseActivation(shell: String) async {
        guard miseActivating == nil else { return }
        miseActivating = shell
        let result = await Task.detached(priority: .userInitiated) {
            MiseProbe.writeActivation(shell)
        }.value
        miseActivating = nil
        if result.ok {
            show(.success(result.trimmedOut))
        } else {
            show(.error(result.errorText))
        }
        await loadMise()
    }

    func installMiseTool(_ spec: String) async {
        guard miseBusy == nil else { return }
        miseBusy = L.t("正在安装 %@…", spec)
        let result = await MiseProbe.install(spec)
        miseBusy = nil
        if result.ok {
            show(.success(L.t("%@ 安装完成", spec)))
        } else {
            show(.error(L.t("%@ 安装失败：%@", spec, Summarize.error(result.errorText))))
        }
        await loadMise()
    }

    func uninstallMiseTool(_ tool: MiseTool) async {
        guard miseBusy == nil else { return }
        miseBusy = L.t("正在卸载 %@…", tool.id)
        let result = await MiseProbe.uninstall("\(tool.name)@\(tool.version)")
        miseBusy = nil
        if result.ok {
            show(.success(L.t("已卸载 %@", tool.id)))
        } else {
            show(.error(L.t("卸载失败：%@", Summarize.error(result.errorText))))
        }
        await loadMise()
    }

    func upgradeMiseTool(_ tool: MiseTool) async {
        guard miseBusy == nil else { return }
        miseBusy = L.t("正在升级 %@…", tool.name)
        let result = await MiseProbe.upgrade(tool.name)
        miseBusy = nil
        if result.ok {
            show(.success(L.t("%@ 已升级", tool.name)))
        } else {
            show(.error(L.t("升级失败：%@", Summarize.error(result.errorText))))
        }
        await loadMise()
    }

    func selfUpdateMise() async {
        guard miseBusy == nil else { return }
        miseBusy = L.t("正在升级 mise…")
        let result = await MiseProbe.selfUpdate()
        miseBusy = nil
        if result.ok {
            show(.success(L.t("mise 已升级到最新版")))
        } else {
            show(.error(L.t("升级失败：%@", Summarize.error(result.errorText))))
        }
        await loadMise()
    }

    func installMise() async {
        guard miseBusy == nil, let brew = Shell.brewPath else { return }
        miseBusy = L.t("正在安装 mise…")
        let result = await Shell.runAsync(brew, ["install", "mise"], timeout: 1800)
        miseBusy = nil
        BrewCache.shared.invalidate()
        if result.ok {
            show(.success(L.t("mise 安装完成")))
        } else {
            show(.error(L.t("mise 安装失败：%@", Summarize.error(result.errorText))))
        }
        await loadMise()
    }

    // MARK: Docker / OrbStack

    func loadDocker() async {
        if dockerLoading { return }
        dockerLoading = true
        let snapshot = await Task.detached(priority: .userInitiated) {
            DockerProbe.scan()
        }.value
        docker = snapshot
        dockerLoading = false
    }

    func startContainer(_ container: DockerContainer) async {
        await runContainerAction(container, verb: .start) {
            await DockerProbe.start(container)
        }
    }

    func stopContainer(_ container: DockerContainer) async {
        await runContainerAction(container, verb: .stop) {
            await DockerProbe.stop(container)
        }
    }

    func restartContainer(_ container: DockerContainer) async {
        await runContainerAction(container, verb: .restart) {
            await DockerProbe.restart(container)
        }
    }

    func removeContainer(_ container: DockerContainer) async {
        await runContainerAction(container, verb: .remove) {
            await DockerProbe.remove(container)
        }
    }

    func startOrb() async {
        guard dockerBusy == nil else { return }
        dockerBusy = L.t("正在启动 OrbStack…")
        let result = await DockerProbe.startOrb()
        dockerBusy = nil
        if result.ok {
            show(.success(L.t("OrbStack 已启动")))
        } else {
            show(.error(L.t("启动 OrbStack 失败：%@", Summarize.error(result.errorText))))
        }
        await loadDocker()
    }

    func stopOrb() async {
        guard dockerBusy == nil else { return }
        dockerBusy = L.t("正在停止 OrbStack…")
        let result = await DockerProbe.stopOrb()
        dockerBusy = nil
        if result.ok {
            show(.success(L.t("OrbStack 已停止")))
        } else {
            show(.error(L.t("停止 OrbStack 失败：%@", Summarize.error(result.errorText))))
        }
        await loadDocker()
    }

    private func runContainerAction(
        _ container: DockerContainer,
        verb: ContainerVerb,
        action: () async -> CommandResult
    ) async {
        guard dockerBusy == nil else { return }
        dockerBusy = verb.doing(container.name)
        let result = await action()
        dockerBusy = nil
        if result.ok {
            show(.success(verb.done(container.name)))
        } else {
            show(.error(verb.failed(container.name, Summarize.error(result.errorText))))
        }
        await loadDocker()
    }

    // MARK: 语言

    func setLanguage(_ lang: Lang) {
        self.lang = lang
        L10n.setLanguage(lang)
    }
}
