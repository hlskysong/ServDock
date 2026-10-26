import Foundation

/// 命令行动作入口：`ServDock --action start redis`
/// 与界面按钮走完全相同的 AppModel 路径，便于自检与脚本化
@MainActor
enum ActionRunner {
    /// `--out <path>` 时把命令行结果写入文件（GUI 启动方式下 stdout 不可见）
    static var outputPath: String?

    private static func emit(_ line: String) {
        print(line)
        guard let outputPath else { return }
        let text = line + "\n"
        if let handle = FileHandle(forWritingAtPath: outputPath) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(toFile: outputPath, atomically: true, encoding: .utf8)
        }
    }

    static func run(verb: ServiceVerb, id: String) async {
        let model = AppModel(autoStart: false)
        await model.refresh(showSpinner: false)

        guard model.item(id) != nil else {
            emit("未知服务: \(id)")
            return
        }
        guard let before = model.item(id) else { return }
        if !before.installed {
            emit("\(id) 未安装，先执行 brew install \(id)")
            return
        }

        let started = Date()
        await model.performAsync(verb, id)
        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(started))

        if let after = model.item(id) {
            let ports = after.ports.map(String.init).joined(separator: ",")
            let pid = after.pid.map(String.init) ?? "-"
            emit("\(id): \(before.status.rawValue) -> \(after.status.rawValue)  pid=\(pid)  ports=[\(ports)]  耗时 \(elapsed)")
        }
        if let toast = model.toast {
            emit("提示: \(toast.text)")
        }
        if let error = model.item(id)?.lastError {
            emit("错误: \(error)")
        }
    }
}
