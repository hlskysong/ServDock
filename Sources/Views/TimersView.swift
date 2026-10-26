import SwiftUI

struct TimersView: View {
    @EnvironmentObject var model: AppModel

    @State private var logText = ""
    private let tick = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    statsRow
                    content
                    hintRow
                }
                .padding(.horizontal, Metrics.pagePadding)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            Task { await model.loadTimers() }
        }
        .onReceive(tick) { _ in
            Task { await model.loadTimers() }
        }
        .sheet(isPresented: Binding(
            get: { model.timerLogJob != nil },
            set: { if !$0 { model.timerLogJob = nil } }
        )) {
            logSheet
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("定时任务"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 12)
            SearchField(text: $model.searchText, placeholder: "搜索任务")
            IconButton(systemImage: "arrow.clockwise", size: 26, help: "刷新（⌘R）") {
                Task {
                    await model.loadTimers()
                    await model.refresh(showSpinner: false)
                }
            }
        }
        .padding(.horizontal, Metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        let jobs = model.timers.jobs
        guard !jobs.isEmpty else { return L.t("launchd 与 cron 定时任务") }
        return L.t("launchd %d 个 · 运行中 %d 个 · cron %d 条",
                   jobs.count, model.timerRunningCount, model.timers.cron.count)
    }

    private var hintRow: some View {
        Text(L.t("系统守护进程启停需要管理员授权 · cron 任务在终端里编辑 · 数据每 6 秒刷新"))
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: 统计 + 过滤

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                metric(L.t("定时触发"), "\(model.timers.jobs.filter { $0.isTimed }.count)", Theme.purple, "calendar.badge.clock")
                metric(L.t("运行中"), "\(model.timerRunningCount)", Theme.green, "play.circle.fill")
                metric(L.t("异常"), "\(model.timerProblemCount)",
                       model.timerProblemCount > 0 ? Theme.red : Theme.textTertiary,
                       "exclamationmark.triangle.fill")
                metric(L.t("cron"), "\(model.timers.cron.count)", Theme.blue, "terminal.fill")
                Spacer(minLength: 0)
            }
            filterRow
        }
    }

    private var filterRow: some View {
        HStack(spacing: 5) {
            ForEach(AppModel.TimerScopeFilter.allCases) { filter in
                let selected = model.timerScopeFilter == filter
                Button {
                    model.timerScopeFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(selected ? Theme.card : Color.clear))
                        .overlay(Capsule().strokeBorder(selected ? Theme.border : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            if model.timersLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.6)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.cardSoft))
    }

    private func metric(_ label: String, _ value: String, _ tint: Color, _ symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }

    // MARK: 列表

    @ViewBuilder
    private var content: some View {
        let jobs = model.filteredJobs
        let timed = jobs.filter { $0.isTimed }
        let agents = jobs.filter { !$0.isTimed }
        let cron = model.filteredCron

        if model.timerScopeFilter != .cron, !timed.isEmpty {
            jobSection(title: "定时触发", note: "按日历或间隔自动执行", jobs: timed)
        }
        if model.timerScopeFilter != .cron, !agents.isEmpty {
            jobSection(title: "常驻与登录启动", note: "KeepAlive / RunAtLoad，没有时间规则", jobs: agents)
        }
        if model.timerScopeFilter != .timed, model.timerScopeFilter != .agents {
            cronSection(cron)
        }
        if model.timerScopeFilter != .cron, timed.isEmpty, agents.isEmpty, cron.isEmpty {
            VStack(spacing: 0) {
                EmptyStateView(
                    symbol: "clock.badge.xmark",
                    title: "没有匹配的定时任务",
                    message: model.searchText.isEmpty
                        ? "launchd 的 LaunchAgents / LaunchDaemons 与 crontab 都会显示在这里。"
                        : "换个关键词试试。"
                )
            }
            .cardSurface()
        }
    }

    private func jobSection(title: String, note: String, jobs: [LaunchdJob]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: title, note: note, count: L.t("%d 个", jobs.count))
            VStack(spacing: 0) {
                ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                    TimerRow(job: job)
                    if index < jobs.count - 1 {
                        Rectangle()
                            .fill(Theme.border.opacity(0.55))
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 3)
            .cardSurface()
        }
    }

    private func sectionHeader(title: String, note: String, count: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L.t(title))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(L.t(note))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(count)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private func cronSection(_ entries: [CronEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                sectionHeader(title: "cron 定时任务", note: "用户 crontab", count: L.t("%d 条", entries.count))
                PillButton(title: "编辑 crontab", systemImage: "terminal", compact: true) {
                    model.editCron()
                }
            }

            if !model.timers.cronReadable {
                cardContainer {
                    EmptyStateView(
                        symbol: "terminal",
                        title: "读不到 crontab",
                        message: model.timers.cronError ?? "当前环境不允许读取 crontab"
                    )
                }
            } else if entries.isEmpty {
                cardContainer {
                    EmptyStateView(
                        symbol: "terminal",
                        title: "没有 cron 任务",
                        message: "cron 适合按分钟粒度的定时脚本，点右上角可以直接编辑。"
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        CronRow(entry: entry)
                        if index < entries.count - 1 {
                            Rectangle()
                                .fill(Theme.border.opacity(0.55))
                                .frame(height: 1)
                                .padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 3)
                .cardSurface()
            }
        }
    }

    private func cardContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .cardSurface()
    }

    // MARK: 日志

    private var logSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                IconBadge(symbol: "doc.text.magnifyingglass", tint: Theme.teal, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.timerLogJob?.label ?? L.t("日志"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let path = model.timerLogJob?.logPath {
                        Text(path.replacingOccurrences(of: Shell.home, with: "~"))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                PillButton(title: "刷新", systemImage: "arrow.clockwise", compact: true) { loadLog() }
                IconButton(systemImage: "xmark", size: 22, help: "关闭") { model.timerLogJob = nil }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView(.vertical) {
                Text(logText.isEmpty ? L.t("（暂无日志输出）") : logText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(width: 620, height: 380)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.cardSoft))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 652)
        .background(Theme.page)
        .onAppear { loadLog() }
    }

    private func loadLog() {
        guard let job = model.timerLogJob, let path = job.logPath else {
            logText = L.t("这个任务没有配置 StandardOutPath / StandardErrorPath，所以没有日志文件。")
            return
        }
        logText = LogLocator.tail(path, maxBytes: 80_000)
    }
}

// MARK: - launchd 任务行

struct TimerRow: View {
    let job: LaunchdJob

    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    private var busy: Bool { model.timerBusy == job.id }

    private var tint: Color {
        if job.pid != nil { return Theme.green }
        if job.scope == .user { return Theme.blue }
        return Theme.slate
    }
    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: job.schedule.symbol, tint: tint, size: 30)

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 5) {
                    Text(job.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if job.scope != .user {
                        TagChip(text: job.scope.title, tint: Theme.amber)
                    }
                    if job.isBrewAgent {
                        TagChip(text: "brew", tint: Theme.slate)
                    }
                    if job.isServDockAgent {
                        TagChip(text: "启服", tint: Theme.accent)
                    }
                    if !job.enabled {
                        TagChip(text: "已禁用", tint: Theme.red)
                    }
                    Spacer(minLength: 4)
                    JobStatusPill(job: job)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text(job.schedule.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(job.isTimed ? Theme.purple : Theme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let next = job.nextRunText {
                        Text(L.t("下次 %@", next))
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize()
                    }
                    Text("·")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize()
                    Text(shortProgram)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)

            if job.loaded {
                PillButton(
                    title: job.scope == .user ? L.t("卸载") : L.t("停止"),
                    systemImage: "stop.fill",
                    compact: true,
                    enabled: !busy
                ) {
                    Task { await model.performTimer(.unload, job: job) }
                }
            } else {
                PillButton(
                    title: job.scope == .user ? L.t("加载") : L.t("启动"),
                    systemImage: "play.fill",
                    tint: Theme.green,
                    kind: .ghost,
                    compact: true,
                    enabled: !busy
                ) {
                    Task { await model.performTimer(.load, job: job) }
                }
            }

            IconButton(systemImage: "bolt.fill", size: 22, help: "立即运行一次") {
                Task { await model.performTimer(.run, job: job) }
            }
            IconButton(systemImage: "doc.text.magnifyingglass", size: 22, help: "查看日志") {
                model.timerLogJob = job
            }
            if hovering {
                IconButton(systemImage: "folder", size: 22, help: "在 Finder 中显示 plist") {
                    model.revealJobPlist(job)
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(hovering ? Theme.cardHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.1)) { hovering = value }
        }
        .contextMenu {
            Button(L.t("加载")) { Task { await model.performTimer(.load, job: job) } }
                .disabled(job.loaded)
            Button(L.t("卸载")) { Task { await model.performTimer(.unload, job: job) } }
                .disabled(!job.loaded)
            Button(L.t("立即运行一次")) { Task { await model.performTimer(.run, job: job) } }
            Divider()
            Button(job.enabled ? L.t("禁用（开机不加载）") : L.t("启用")) {
                Task { await model.toggleTimer(job) }
            }
            Divider()
            Button(L.t("查看日志")) { model.timerLogJob = job }
            Button(L.t("在 Finder 中显示 plist")) { model.revealJobPlist(job) }
            Button(L.t("复制命令")) { model.copyToPasteboard(job.commandPreview, label: "命令") }
        }
        .help(job.commandPreview)
    }

    private var shortProgram: String {
        let path = job.program.replacingOccurrences(of: Shell.home, with: "~")
        let args = job.args.prefix(2).joined(separator: " ")
        return args.isEmpty ? path : "\(path) \(args)"
    }
}

// MARK: - cron 行

struct CronRow: View {
    let entry: CronEntry

    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "calendar", tint: Theme.blue, size: 30)
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 5) {
                    Text(entry.comment ?? shortCommand)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    TagChip(text: entry.expression, tint: Theme.slate)
                    Spacer(minLength: 4)
                    Text(entry.scheduleText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.purple)
                }
                Text(entry.command)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if hovering {
                IconButton(systemImage: "doc.on.doc", size: 22, help: "复制命令") {
                    model.copyToPasteboard(entry.command, label: "命令")
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(hovering ? Theme.cardHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.1)) { hovering = value }
        }
        .contextMenu {
            Button(L.t("复制命令")) { model.copyToPasteboard(entry.command, label: "命令") }
            Button(L.t("编辑 crontab")) { model.editCron() }
        }
    }

    private var shortCommand: String {
        let parts = entry.command.split(separator: " ").map(String.init)
        return parts.last.map { ($0 as NSString).lastPathComponent } ?? entry.command
    }
}

// MARK: - 任务状态胶囊

struct JobStatusPill: View {
    let job: LaunchdJob

    private var tint: Color {
        if job.pid != nil { return Theme.green }
        if job.loaded {
            if let exit = job.lastExit, exit != 0 { return Theme.red }
            return Theme.blue
        }
        return Theme.textTertiary
    }

    private var text: String {
        if let pid = job.pid { return L.t("运行中 · %d", pid) }
        if job.loaded {
            if let exit = job.lastExit, exit != 0 { return L.t("退出 %d", exit) }
            return "已加载"
        }
        return "未加载"
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}
