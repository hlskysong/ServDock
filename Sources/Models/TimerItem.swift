import Foundation

/// launchd 定时任务的触发规则
enum LaunchdSchedule: Sendable, Hashable {
    case none
    case interval(Int)
    case calendar([CalendarRule])
    case keepAlive
    case atLoad

    struct CalendarRule: Sendable, Hashable {
        var minute: Int?
        var hour: Int?
        var day: Int?
        var weekday: Int?   // 0 / 7 = 周日
        var month: Int?

        var text: String {
            let time: String
            switch (hour, minute) {
            case let (h?, m?): time = String(format: "%02d:%02d", h, m)
            case let (h?, nil): time = String(format: "%02d:00", h)
            case let (nil, m?): time = L.t("每小时第 %d 分", m)
            default: time = L.t("每分钟")
            }
            if let month, let day { return L.t("每年 %d 月 %d 日 %@", month, day, time) }
            if let month { return L.t("每年 %d 月每天 %@", month, time) }
            if let day { return L.t("每月 %d 日 %@", day, time) }
            if let weekday {
                let names = [
                    L.t("周日"), L.t("周一"), L.t("周二"), L.t("周三"),
                    L.t("周四"), L.t("周五"), L.t("周六")
                ]
                let day = names[max(0, min(6, weekday % 7))]
                return L.t("每%@ %@", day, time)
            }
            return L.t("每天 %@", time)
        }
    }

    /// 是否有真实定时规则
    var isTimed: Bool {
        switch self {
        case .interval, .calendar: return true
        case .none, .keepAlive, .atLoad: return false
        }
    }

    var text: String {
        switch self {
        case .none: return L.t("手动触发")
        case .interval(let seconds):
            if seconds % 3600 == 0 { return L.t("每 %d 小时", seconds / 3600) }
            if seconds % 60 == 0 { return L.t("每 %d 分钟", seconds / 60) }
            return L.t("每 %d 秒", seconds)
        case .calendar(let rules):
            guard !rules.isEmpty else { return L.t("定时（规则无效）") }
            return rules.map(\.text).joined(separator: " · ")
        case .keepAlive: return L.t("常驻（KeepAlive）")
        case .atLoad: return L.t("登录时运行")
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar.badge.clock"
        case .interval: return "clock.arrow.circlepath"
        case .keepAlive: return "bolt.heart"
        case .atLoad: return "power"
        case .none: return "hand.tap"
        }
    }

    /// 下一次触发时间（只对 StartCalendarInterval 计算）
    func nextRun(after now: Date = Date()) -> Date? {
        guard case .calendar(let rules) = self, !rules.isEmpty else { return nil }
        let calendar = Calendar.current
        var best: Date?
        for rule in rules {
            guard let candidate = Self.nextDate(rule: rule, after: now, calendar: calendar) else { continue }
            if let current = best {
                if candidate < current { best = candidate }
            } else {
                best = candidate
            }
        }
        return best
    }

    private static func nextDate(rule: CalendarRule, after now: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let targetMinute = rule.minute ?? 0
        let targetHour = rule.hour ?? components.hour ?? 0

        guard var probe = calendar.date(from: DateComponents(
            year: components.year,
            month: rule.month ?? components.month,
            day: rule.day ?? components.day,
            hour: targetHour,
            minute: targetMinute
        )) else { return nil }

        // 逐日推进，找第一个满足条件的时刻（最多一年）
        for _ in 0..<400 {
            let parts = calendar.dateComponents([.month, .day, .weekday], from: probe)
            var matches = true
            if let month = rule.month, parts.month != month { matches = false }
            if let day = rule.day, parts.day != day { matches = false }
            if let weekday = rule.weekday, (parts.weekday ?? 1) - 1 != weekday % 7 { matches = false }
            if let hour = rule.hour, targetHour != hour { matches = false }
            if matches, probe > now { return probe }
            guard let next = calendar.date(byAdding: .day, value: 1, to: probe) else { return nil }
            probe = next
            components = calendar.dateComponents([.year, .month, .day], from: probe)
        }
        return nil
    }
}

/// 一个 launchd 任务（用户代理 / 系统守护进程）
struct LaunchdJob: Identifiable, Sendable, Hashable {
    enum Scope: String, Sendable {
        case user
        case system
        case systemAgent

        var title: String {
            switch self {
            case .user: return L.t("用户代理")
            case .system: return L.t("系统守护进程")
            case .systemAgent: return L.t("系统代理")
            }
        }

        var needsAdmin: Bool { self != .user }
    }

    var scope: Scope
    var label: String
    var plistPath: String
    var program: String
    var args: [String]
    var schedule: LaunchdSchedule
    var runAtLoad = false
    var keepAlive = false
    var disabledInPlist = false
    var stdoutPath: String?
    var stderrPath: String?
    var modified: Date?

    // 运行态（由启动器补齐）
    var loaded = false
    var enabled = true
    var pid: Int?
    var lastExit: Int?

    var id: String { scope.rawValue + ":" + label }

    var programName: String { (program as NSString).lastPathComponent }

    /// 定时任务 / 常驻任务 / 纯手动
    var isTimed: Bool { schedule.isTimed }

    /// Homebrew 生成的 agent
    var isBrewAgent: Bool {
        SystemProbe.serviceLabelPrefixes.contains { label.hasPrefix($0) }
    }

    /// 启服自己生成的 agent（含改名前的 local.servicedock.* 前缀）
    var isServDockAgent: Bool { Brand.isAgentLabel(label) }

    var nextRunText: String? {
        guard let date = schedule.nextRun() else { return nil }
        return TimeText.stamp(date)
    }

    /// 命令预览
    var commandPreview: String {
        ([program] + args).joined(separator: " ")
    }

    var logPath: String? {
        if let stdoutPath, Paths.exists(stdoutPath) { return stdoutPath }
        if let stderrPath, Paths.exists(stderrPath) { return stderrPath }
        return nil
    }
}

/// crontab 里的一行任务
struct CronEntry: Identifiable, Sendable, Hashable {
    var minutes: String
    var hours: String
    var days: String
    var months: String
    var weekdays: String
    var command: String
    var comment: String?
    var rawLine: String

    var id: String { rawLine }

    var expression: String {
        "\(minutes) \(hours) \(days) \(months) \(weekdays)"
    }

    /// 尽量翻译成人话，翻不动就原样展示
    var scheduleText: String {
        let field = [minutes, hours, days, months, weekdays]
        if field == ["*", "*", "*", "*", "*"] { return L.t("每分钟") }
        if minutes.hasPrefix("*/"), hours == "*", days == "*", months == "*", weekdays == "*" {
            return L.t("每 %@ 分钟", String(minutes.dropFirst(2)))
        }
        if minutes.hasPrefix("*/"), hours == "*" {
            return L.t("每 %@ 分钟", String(minutes.dropFirst(2)))
        }
        if let m = Int(minutes), let h = Int(hours), days == "*", months == "*" {
            let time = String(format: "%02d:%02d", h, m)
            if weekdays == "*" { return L.t("每天 %@", time) }
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            if let w = Int(weekdays), (0...7).contains(w) {
                return L.t("每%@ %@", names[w % 7], time)
            }
        }
        if minutes == "0", hours == "*", days == "*", months == "*", weekdays == "*" {
            return L.t("每小时整点")
        }
        return expression
    }
}

/// 定时任务快照
struct TimerSnapshot: Sendable {
    var jobs: [LaunchdJob] = []
    var cron: [CronEntry] = []
    /// 是否能读 crontab（自动化环境可能不允许）
    var cronReadable = false
    var cronError: String?
}
