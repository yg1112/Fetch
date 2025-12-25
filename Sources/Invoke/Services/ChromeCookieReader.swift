import Foundation
import Security
import SQLite3

/// 直接从 Chrome Cookie 数据库读取 Cookie（包括 HttpOnly）
/// 这是获取完整登录状态的唯一方法
class ChromeCookieReader {
    static let shared = ChromeCookieReader()
    
    /// 浏览器 Cookie 数据库路径
    private let browserPaths: [(name: String, path: String, keyService: String)] = [
        ("Chrome", "Google/Chrome/Default/Cookies", "Chrome Safe Storage"),
        ("Arc", "Arc/User Data/Default/Cookies", "Arc Safe Storage"),
        ("Brave", "BraveSoftware/Brave-Browser/Default/Cookies", "Brave Safe Storage"),
        ("Edge", "Microsoft Edge/Default/Cookies", "Microsoft Edge Safe Storage")
    ]
    
    /// 从浏览器数据库读取 Google 相关 Cookie
    func readGoogleCookies(completion: @escaping (Result<[HTTPCookie], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 尝试每个浏览器
            for browser in self.browserPaths {
                let dbPath = NSHomeDirectory() + "/Library/Application Support/" + browser.path
                
                guard FileManager.default.fileExists(atPath: dbPath) else {
                    continue
                }
                
                print("🔍 尝试读取 \(browser.name) Cookie 数据库...")
                
                // 获取解密密钥
                guard let key = self.getDecryptionKey(service: browser.keyService) else {
                    print("⚠️ 无法获取 \(browser.name) 解密密钥")
                    continue
                }
                
                // 读取并解密 Cookie
                do {
                    let cookies = try self.readCookiesFromDB(path: dbPath, key: key)
                    if !cookies.isEmpty {
                        print("✅ 从 \(browser.name) 读取到 \(cookies.count) 个 Google Cookie")
                        DispatchQueue.main.async {
                            completion(.success(cookies))
                        }
                        return
                    }
                } catch {
                    print("❌ 读取 \(browser.name) Cookie 失败: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                completion(.failure(CookieReaderError.noCookiesFound))
            }
        }
    }
    
    /// 从 Keychain 获取 Chrome Safe Storage 密钥
    private func getDecryptionKey(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        
        print("⚠️ Keychain 查询失败: \(status)")
        return nil
    }
    
    /// 从 SQLite 数据库读取 Cookie
    private func readCookiesFromDB(path: String, key: Data) throws -> [HTTPCookie] {
        var db: OpaquePointer?
        
        // 复制数据库到临时位置（避免锁定问题）
        let tempPath = NSTemporaryDirectory() + "fetch_cookies_\(UUID().uuidString).db"
        try FileManager.default.copyItem(atPath: path, toPath: tempPath)
        defer {
            try? FileManager.default.removeItem(atPath: tempPath)
        }
        
        guard sqlite3_open_v2(tempPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CookieReaderError.dbOpenFailed
        }
        defer { sqlite3_close(db) }
        
        // 查询 Google 相关 Cookie
        let query = """
            SELECT host_key, name, encrypted_value, path, expires_utc, is_secure, is_httponly
            FROM cookies
            WHERE host_key LIKE '%google.com'
        """
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw CookieReaderError.queryFailed
        }
        defer { sqlite3_finalize(statement) }
        
        var cookies: [HTTPCookie] = []
        
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let hostPtr = sqlite3_column_text(statement, 0),
                  let namePtr = sqlite3_column_text(statement, 1) else {
                continue
            }
            
            let host = String(cString: hostPtr)
            let name = String(cString: namePtr)
            
            // 获取加密的 value
            let encryptedBlob = sqlite3_column_blob(statement, 2)
            let encryptedLength = sqlite3_column_bytes(statement, 2)
            
            var value = ""
            if let blob = encryptedBlob, encryptedLength > 0 {
                let encryptedData = Data(bytes: blob, count: Int(encryptedLength))
                value = decryptCookieValue(encryptedData, key: key) ?? ""
            }
            
            let pathPtr = sqlite3_column_text(statement, 3)
            let path = pathPtr != nil ? String(cString: pathPtr!) : "/"
            
            let expiresUtc = sqlite3_column_int64(statement, 4)
            let isSecure = sqlite3_column_int(statement, 5) == 1
            
            // Chrome 时间戳是从 1601-01-01 开始的微秒数
            let chromeEpoch = Date(timeIntervalSince1970: -11644473600)
            let expiresDate = Date(timeInterval: Double(expiresUtc) / 1_000_000, since: chromeEpoch)
            
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: host,
                .path: path,
                .name: name,
                .value: value,
                .expires: expiresDate
            ]
            
            if isSecure {
                properties[.secure] = "TRUE"
            }
            
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }
        
        return cookies
    }
    
    /// 解密 Chrome Cookie 值 (AES-128-CBC with PBKDF2)
    private func decryptCookieValue(_ encrypted: Data, key: Data) -> String? {
        // Chrome v10+ 格式: "v10" + 12字节 nonce + 加密数据 + 16字节 tag
        // 或者 "v11" 格式
        guard encrypted.count > 3 else { return nil }
        
        let prefix = String(data: encrypted.prefix(3), encoding: .utf8)
        
        if prefix == "v10" || prefix == "v11" {
            // AES-256-GCM 加密
            return decryptAESGCM(encrypted, key: key)
        } else {
            // 旧版 AES-128-CBC 加密 (macOS)
            return decryptAESCBC(encrypted, key: key)
        }
    }
    
    /// AES-GCM 解密 (Chrome v10+)
    /// 注意：CommonCrypto 不支持 GCM，需要使用 CryptoKit
    /// 但 macOS 上的 Chrome 通常使用 v10 格式，我们尝试 CBC 回退
    private func decryptAESGCM(_ encrypted: Data, key: Data) -> String? {
        // v10/v11 格式在 macOS 上使用 AES-GCM，CommonCrypto 不支持
        // 尝试跳过版本前缀后使用 CBC 解密
        let dataWithoutPrefix = encrypted.dropFirst(3)
        return decryptAESCBC(Data(dataWithoutPrefix), key: key)
    }
    
    /// AES-CBC 解密 (旧版 macOS Chrome)
    private func decryptAESCBC(_ encrypted: Data, key: Data) -> String? {
        // 派生密钥 (PBKDF2)
        let salt = "saltysalt".data(using: .utf8)!
        let iterations: UInt32 = 1003
        var derivedKey = [UInt8](repeating: 0, count: 16)
        
        key.withUnsafeBytes { keyPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    keyPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                    key.count,
                    saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    iterations,
                    &derivedKey,
                    16
                )
            }
        }
        
        // IV 是 16 个空格
        let iv = [UInt8](repeating: 0x20, count: 16)
        
        var decryptedBytes = [UInt8](repeating: 0, count: encrypted.count + kCCBlockSizeAES128)
        var decryptedLength = 0
        
        let status = encrypted.withUnsafeBytes { encryptedPtr in
            CCCrypt(
                CCOperation(kCCDecrypt),
                CCAlgorithm(kCCAlgorithmAES),
                CCOptions(kCCOptionPKCS7Padding),
                derivedKey,
                derivedKey.count,
                iv,
                encryptedPtr.baseAddress,
                encrypted.count,
                &decryptedBytes,
                decryptedBytes.count,
                &decryptedLength
            )
        }
        
        guard status == kCCSuccess else { return nil }
        
        return String(bytes: decryptedBytes.prefix(decryptedLength), encoding: .utf8)
    }
    
    enum CookieReaderError: Error, LocalizedError {
        case noCookiesFound
        case dbOpenFailed
        case queryFailed
        case decryptionFailed
        
        var errorDescription: String? {
            switch self {
            case .noCookiesFound:
                return "未找到浏览器 Cookie，请确保已在浏览器中登录 Google"
            case .dbOpenFailed:
                return "无法打开 Cookie 数据库，请关闭浏览器后重试"
            case .queryFailed:
                return "查询 Cookie 失败"
            case .decryptionFailed:
                return "Cookie 解密失败"
            }
        }
    }
}

// CommonCrypto 桥接
import CommonCrypto

