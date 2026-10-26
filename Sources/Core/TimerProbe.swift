import Foundation

/// 定时任务探测：launchd plists + crontab，全部只读
enum TimerProbe {

    static func scan() -> TimerSnapshot {
        var snapshot = TimerSnapshot()
        let entries = Launchctl.list()
        var byLabel: [String: Launchctl.Entry] = [:]
        for entry in entries { byLabel[entry.label] = entry }
        let processes = SystemProbe.processTable()
        let disabledUser = disabledMap(domain: Launchctl.userDomain)
        let disabledSystem = disabledMap(domain: "system")

        var jobs: [LaunchdJob] = []
        jobs.append(contentsOf: scan(directory: Shell.home + "/Library/LaunchAgents", scope: .user))
        jobs.append(contentsOf: scan(directory: "/Library/LaunchAgents", scope: .systemAgent))
        jobs.append(contentsOf: scan(directory: "/Library/LaunchDaemons", scope: .system))

        for index in jobs.indices {
            let job = jobs[index]
            if let entry = byLabel[job.label] {
                jobs[index].loaded = true
                jobs[index].pid = entry.pid
                jobs[index].lastExit = entry.lastExit
            } else if job.scope != .user {
                // 系统域：launchctl print system/<label> 非特权也能读
                if let state = systemState(label: job.label) {
                    jobs[index].loaded = state.loaded
                    jobs[index].pid = state.pid
                    jobs[index].lastExit = state.lastExit
                } else if let process = matchProcess(job, in: processes) {
                    // 兜底：进程表
                    jobs[index].pid = process.pid
                    jobs[index].loaded = true
                }
            }
            let map = job.scope.needsAdmin ? disabledSystem : disabledUser
            if let disabled = map[job.label] {
                jobs[index].enabled = !disabled
            }
        }

        snapshot.jobs = jobs.sorted { lhs, rhs in
            if lhs.scope != rhs.scope { return lhs.scope.rawValue < rhs.scope.rawValue }
            if lhs.isTimed != rhs.isTimed { return lhs.isTimed }
            return lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }

        loadCron(into: &snapshot)
        return snapshot
    }

    // MARK: - launchd

    private static func scan(directory: String, scope: LaunchdJob.Scope) -> [LaunchdJob] {
        guard Paths.isDirectory(directory),
              let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var jobs: [LaunchdJob] = []
        for name in entries where name.hasSuffix(".plist") {
            guard !name.hasPrefix(".") else { continue }
            let path = directory + "/" + name
            if let job = parse(plist: path, scope: scope) {
                jobs.append(job)
            }
        }
        return jobs
    }

    private static func parse(plist path: String, scope: LaunchdJob.Scope) -> LaunchdJob? {
        guard let data = FileManager.default.contents(atPath: path),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        let label = (dict["Label"] as? String) ?? (path as NSString).lastPathComponent.replacingOccurrences(of: ".plist", with: "")
        // 系统自带的一大堆任务不展示，避免噪音
        guard !label.hasPrefix("com.apple.") else { return nil }

        var programArguments: [String] = []
        if let args = dict["ProgramArguments"] as? [String] {
            programArguments = args
        } else if let program = dict["Program"] as? String {
            programArguments = [program]
        }
        guard !programArguments.isEmpty else { return nil }

        let program = programArguments[0]
        let args = Array(programArguments.dropFirst())

        // 定时规则
        var schedule: LaunchdSchedule = .none
        if let calendarField = dict["StartCalendarInterval"] {
            let rules = parseCalendar(calendarField)
            if !rules.isEmpty { schedule = .calendar(rules) }
        }
        if case .none = schedule, let interval = dict["StartInterval"] as? Int, interval > 0 {
            schedule = .interval(interval)
        }

        var keepAlive = false
        if let value = dict["KeepAlive"] {
            if let flag = value as? Bool {
                keepAlive = flag
            } else if value is [String: Any] {
                keepAlive = true
            }
        }
        let runAtLoad = (dict["RunAtLoad"] as? Bool) ?? false

        if case .none = schedule {
            if keepAlive {
                schedule = .keepAlive
            } else if runAtLoad {
                schedule = .atLoad
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)

        return LaunchdJob(
            scope: scope,
            label: label,
            plistPath: path,
            program: program,
            args: args,
            schedule: schedule,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            disabledInPlist: (dict["Disabled"] as? Bool) ?? false,
            stdoutPath: dict["StandardOutPath"] as? String,
            stderrPath: dict["StandardErrorPath"] as? String,
            modified: attrs?[.modificationDate] as? Date
        )
    }

    private static func parseCalendar(_ value: Any) -> [LaunchdSchedule.CalendarRule] {
        func rule(from dict: [String: Any]) -> LaunchdSchedule.CalendarRule {
            LaunchdSchedule.CalendarRule(
                minute: dict["Minute"] as? Int,
                hour: dict["Hour"] as? Int,
                day: dict["Day"] as? Int,
                weekday: dict["Weekday"] as? Int,
                month: dict["Month"] as? Int
            )
        }
        if let single = value as? [String: Any] {
            return [rule(from: single)]
        }
        if let list = value as? [[String: Any]] {
            return list.map(rule(from:))
        }
        return []
    }

    private static func matchProcess(_ job: LaunchdJob, in processes: [RunningProcess]) -> RunningProcess? {
        let target = job.programName.lowercased()
        guard !target.isEmpty else { return nil }
        return processes.first { process in
            // command 带参数，先取第一个词再看文件名
            guard let first = process.command.split(separator: " ").first.map(String.init) else { return false }
            let name = (first as NSString).lastPathComponent.lowercased()
            return name == target || first.lowercased() == job.program.lowercased()
        }
    }

    // MARK: - 系统域状态

    struct DomainState {
        var loaded: Bool
        var pid: Int?
        var lastExit: Int?
    }

    /// 读 `launchctl print system/<label>`：非特权也能读到 state / pid / 退出码
    static func systemState(label: String) -> DomainState? {
        let result = Shell.run("/bin/launchctl", ["print", "system/\(label)"], timeout: 15)
        guard result.ok else { return nil }
        var state = DomainState(loaded: true, pid: nil, lastExit: nil)
        for line in result.stdout.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("state = ") {
                let value = text.replacingOccurrences(of: "state = ", with: "")
                state.loaded = !value.contains("not running")
            } else if text.hasPrefix("pid = ") {
                state.pid = Int(text.replacingOccurrences(of: "pid = ", with: ""))
            } else if text.hasPrefix("last exit code = ") {
                state.lastExit = Int(text.replacingOccurrences(of: "last exit code = ", with: ""))
            }
        }
        return state
    }

    /// `launchctl print-disabled <domain>` → label: 是否禁用
    private static func disabledMap(domain: String) -> [String: Bool] {
        let result = Shell.run("/bin/launchctl", ["print-disabled", domain], timeout: 20)
        guard result.ok else { return [:] }
        var map: [String: Bool] = [:]
        for line in result.stdout.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let arrow = text.range(of: "=>") else { continue }
            var label = String(text[..<arrow.lowerBound]).trimmingCharacters(in: .whitespaces)
            label = label.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !label.isEmpty else { continue }
            let value = String(text[arrow.upperBound...]).trimmingCharacters(in: .whitespaces)
            map[label] = value.contains("disabled") || value == "true"
        }
        return map
    }

    // MARK: - cron

    private static func loadCron(into snapshot: inout TimerSnapshot) {
        let result = Shell.run("/usr/bin/crontab", ["-l"], timeout: 20)
        if !result.ok {
            let text = result.errorText
            // "no crontab for user" 说明能读、只是空的
            if text.contains("no crontab") {
                snapshot.cronReadable = true
                snapshot.cronError = nil
                snapshot.cron = []
                return
            }
            snapshot.cronReadable = false
            snapshot.cronError = L.t("无法读取 crontab：%@", Self.firstLine(text))
            return
        }
        snapshot.cronReadable = true

        var pendingComment: String?
        var entries: [CronEntry] = []
        for line in result.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                pendingComment = nil
                continue
            }
            if trimmed.hasPrefix("#") {
                pendingComment = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            // 环境变量行：PATH=... 之类
            if trimmed.contains("="), !trimmed.contains(" ") || trimmed.split(separator: " ").count == 1 {
                continue
            }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 6 else { continue }
            let command = parts.dropFirst(5).joined(separator: " ")
            entries.append(
                CronEntry(
                    minutes: parts[0],
                    hours: parts[1],
                    days: parts[2],
                    months: parts[3],
                    weekdays: parts[4],
                    command: command,
                    comment: pendingComment,
                    rawLine: trimmed
                )
            )
            pendingComment = nil
        }
        snapshot.cron = entries
    }

    private static func firstLine(_ text: String) -> String {
        text.split(separator: "\n").first.map(String.init) ?? text
    }
}
