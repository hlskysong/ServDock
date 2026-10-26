import Foundation

/// 从命令输出里挑一句最能说明问题的文字
enum Summarize {
    static func firstMeaningful(_ text: String, limit: Int = 180) -> String? {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        let error = lines.first {
            $0.hasPrefix("Error") || $0.contains("error:") || $0.contains("failed") || $0.contains("Error:")
        }
        let picked = error ?? lines.last ?? ""
        guard !picked.isEmpty else { return nil }
        if picked.count <= limit { return picked }
        return String(picked.prefix(limit)) + "…"
    }

    /// 带兜底文案的版本
    static func error(_ text: String, limit: Int = 180) -> String {
        firstMeaningful(text, limit: limit) ?? L.t("未知错误")
    }
}
