import Foundation

class GitService {
    static let shared = GitService()
    
    /// 在指定目录下执行 Git 命令
    func run(args: [String], in directory: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        
        // 🔑 配置环境变量，使用缓存的凭据，减少 keychain 弹窗
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0" // 禁用终端提示
        env["GIT_ASKPASS"] = "" // 不使用 askpass
        task.environment = env
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        if task.terminationStatus != 0 {
            throw NSError(domain: "GitError", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
        }
        
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// 🚀 优化的提交流程
    func commitChanges(in directory: String, message: String) throws {
        _ = try run(args: ["add", "."], in: directory)
        _ = try run(args: ["commit", "-m", message], in: directory)
    }
    
    /// Push 到远程
    func pushToRemote(in directory: String) throws {
        try? configureCredentialHelper(in: directory)
        _ = try run(args: ["push"], in: directory)
    }
    
    /// 创建新分支
    func createBranch(in directory: String, name: String) throws {
        _ = try run(args: ["checkout", "-b", name], in: directory)
    }
    
    /// Push 分支到远程
    func pushBranch(in directory: String, branch: String) throws {
        try? configureCredentialHelper(in: directory)
        _ = try run(args: ["push", "-u", "origin", branch], in: directory)
    }
    
    /// 废弃：使用 commitChanges + pushToRemote 代替
    func pushChanges(in directory: String, message: String) throws -> String {
        try commitChanges(in: directory, message: message)
        try pushToRemote(in: directory)
        return "Committed & Pushed: \(message)"
    }
    
    /// 配置 Git credential helper 以缓存凭据
    private func configureCredentialHelper(in directory: String) throws {
        // 使用 osxkeychain helper 并设置缓存时间
        try? run(args: ["config", "credential.helper", "osxkeychain"], in: directory)
        
        // 设置缓存超时（1小时 = 3600秒）
        try? run(args: ["config", "--global", "credential.helper", "cache --timeout=3600"], in: directory)
    }
    
    /// 获取远程仓库 URL（用于构建 commit 链接）
    func getRemoteURL(in directory: String) -> String? {
        guard let remoteURL = try? run(args: ["config", "--get", "remote.origin.url"], in: directory) else {
            return nil
        }
        
        // 转换为 HTTPS GitHub URL
        // git@github.com:user/repo.git -> https://github.com/user/repo
        // https://github.com/user/repo.git -> https://github.com/user/repo
        var url = remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
            .replacingOccurrences(of: ".git", with: "")
        
        return url
    }
    
    /// 构建 GitHub commit URL
    func getCommitURL(for hash: String, in directory: String) -> String? {
        guard let baseURL = getRemoteURL(in: directory) else {
            return nil
        }
        return "\(baseURL)/commit/\(hash)"
    }
    
    func getDiff(in directory: String) -> String {
        // 获取未暂存和已暂存的差异
        let diff = (try? run(args: ["diff"], in: directory)) ?? ""
        let cachedDiff = (try? run(args: ["diff", "--cached"], in: directory)) ?? ""
        return diff + "\n" + cachedDiff
    }
}
