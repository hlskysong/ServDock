import Foundation

/// 命令行诊断：`ServDock --probe` 打印探测结果，方便排查数据来源
enum ProbeRunner {
    static func run() {
        let snap = AppModel.collectSync()

        print("brew        : \(Shell.brewPath ?? "未找到")")
        print("brew prefix : \(Shell.brewPrefix)")
        print("brew version: \(snap.brewVersion)")
        print("services    : \(snap.services.count)")
        for entry in snap.services {
            print("  - \(entry.name)  status=\(entry.status.rawValue)  exit=\(entry.exitCode.map(String.init) ?? "-")  file=\(entry.file ?? "-")")
        }
        print("versions    : \(snap.versions.count)")
        for (name, version) in snap.versions.sorted(by: { $0.key < $1.key }) {
            print("  - \(name) = \(version)")
        }
        print("launchd     : \(snap.launchd.count)")
        for (label, pid) in snap.launchd.sorted(by: { $0.key < $1.key }) {
            print("  - \(label) pid=\(pid)")
        }
        print("listening   : \(snap.portOwners.count)")
        for owner in snap.portOwners where !owner.ports.isEmpty {
            print("  - pid=\(owner.pid) \(owner.command) ports=\(owner.ports.map(String.init).joined(separator: ","))")
        }
        print("pids        : \(snap.processPIDs.count)")
        for (id, pid) in snap.processPIDs.sorted(by: { $0.key < $1.key }) {
            print("  - \(id) pid=\(pid)")
        }
        print("bun         : installed=\(snap.bun.installed) v\(snap.bun.version) path=\(snap.bun.path) tools=\(snap.bun.binTools.count) cache=\(snap.bun.cacheSize) shell=\(snap.bun.shellConfigured)")
        print("node        : fnm=\(snap.node.fnmVersion) root=\(snap.node.rootPath) default=\(snap.node.defaultVersion ?? "-") shell=\(snap.node.shellConfigured)")
        for version in snap.node.versions {
            print("  - \(version.version) npm=\(version.npmVersion ?? "-") size=\(version.size ?? "-") default=\(version.isDefault)")
        }

        print("processes   : \(snap.processes.count)")
        print("non-brew    :")
        for spec in ServiceSpec.catalog where spec.kind != .brew {
            let installed = spec.binaryPath() != nil
                || (spec.daemonPlist.map { Paths.exists($0) } ?? false)
            let pid = snap.processPIDs[spec.id].map(String.init) ?? "-"
            print("  - \(spec.id) kind=\(spec.kind.rawValue) label=\(spec.launchdLabel) installed=\(installed) pid=\(pid) version=\(spec.bundleVersion() ?? snap.versions[spec.id] ?? "-")")
        }

        let timers = TimerProbe.scan()
        print("timers      : jobs=\(timers.jobs.count) cron=\(timers.cron.count) cronReadable=\(timers.cronReadable)")
        for job in timers.jobs {
            let pid = job.pid.map(String.init) ?? "-"
            print("  - [\(job.scope.rawValue)] \(job.label)  loaded=\(job.loaded)  pid=\(pid)  exit=\(job.lastExit.map(String.init) ?? "-")  \(job.schedule.text)  log=\(job.logPath.map { ($0 as NSString).lastPathComponent } ?? "-")")
        }
        for entry in timers.cron {
            print("  - [cron] \(entry.expression)  \(entry.scheduleText)  \(entry.command)")
        }
        if let error = timers.cronError {
            print("cron error  : \(error)")
        }
    }
}
