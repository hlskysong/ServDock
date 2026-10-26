import Foundation

/// 定时任务可执行的动作
enum TimerJobAction: String, Sendable {
    case load
    case unload
    case run
    case enable
    case disable

    var title: String {
        switch self {
        case .load: return L.t("加载")
        case .unload: return L.t("卸载")
        case .run: return L.t("立即运行")
        case .enable: return L.t("启用")
        case .disable: return L.t("禁用")
        }
    }

    var doneText: String {
        switch self {
        case .load: return L.t("已加载")
        case .unload: return L.t("已卸载")
        case .run: return L.t("已触发")
        case .enable: return L.t("已启用")
        case .disable: return L.t("已禁用")
        }
    }
}

extension AppModel {

    // MARK: - 采集

    func loadTimers() async {
        if snapshotMode || timersLoading { return }
        timersLoading = true
        let snapshot = await Task.detached(priority: .userInitiated) { TimerProbe.scan() }.value
        timers = snapshot
        timersLoading = false
    }

    /// 当前筛选后的任务
    var filteredJobs: [LaunchdJob] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var list = timers.jobs
        switch timerScopeFilter {
        case .all: break
        case .timed: list = list.filter { $0.isTimed }
        case .agents: list = list.filter { !$0.isTimed }
        case .cron: list = []
        }
        guard !keyword.isEmpty else { return list }
        return list.filter {
            $0.label.lowercased().contains(keyword)
                || $0.program.lowercased().contains(keyword)
                || $0.schedule.text.lowercased().contains(keyword)
        }
    }

    var filteredCron: [CronEntry] {
        guard timerScopeFilter == .all || timerScopeFilter == .cron else { return [] }
        let keyword = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !keyword.isEmpty else { return timers.cron }
        return timers.cron.filter {
            $0.command.lowercased().contains(keyword) || ($0.comment ?? "").lowercased().contains(keyword)
        }
    }

    var timerRunningCount: Int { timers.jobs.filter { $0.pid != nil }.count }

    var timerProblemCount: Int {
        timers.jobs.filter { $0.loaded && ($0.lastExit ?? 0) != 0 && $0.pid == nil }.count
    }

    // MARK: - 动作

    func performTimer(_ action: TimerJobAction, job: LaunchdJob) async {
        guard timerBusy == nil else { return }
        timerBusy = job.id
        let needsAdmin = job.scope.needsAdmin

        let result: CommandResult
        switch action {
        case .load:
            if Paths.exists(job.plistPath) == false {
                timerBusy = nil
                show(.error(L.t("plist 不存在：%@", job.plistPath)))
                return
            }
            result = needsAdmin
                ? Launchctl.bootstrapSystem(plist: job.plistPath)
                : Launchctl.bootstrap(plist: job.plistPath)
        case .unload:
            result = needsAdmin
                ? Launchctl.bootoutSystem(label: job.label)
                : Launchctl.bootout(label: job.label)
        case .run:
            result = needsAdmin
                ? Launchctl.kickstartSystem(label: job.label)
                : Launchctl.kickstart(label: job.label)
        case .enable, .disable:
            if needsAdmin {
                result = Launchctl.runPrivileged(
                    "/bin/launchctl \(action == .enable ? "enable" : "disable") system/\(job.label)"
                )
            } else {
                result = Launchctl.setEnabled(action == .enable, label: job.label)
            }
        }

        timerBusy = nil
        if result.ok {
            show(.success("\(job.label) \(action.doneText)"))
        } else {
            show(.error(L.t("%@ %@失败：%@", job.label, action.title, Self.summarize(result.errorText))))
        }
        await loadTimers()
    }

    /// 启用/禁用状态（禁用后开机也不会加载）
    func toggleTimer(_ job: LaunchdJob) async {
        await performTimer(job.enabled ? .disable : .enable, job: job)
    }

    func editCron() {
        openInTerminal("crontab -e")
    }

    func revealJobPlist(_ job: LaunchdJob) {
        reveal(job.plistPath)
    }
}
