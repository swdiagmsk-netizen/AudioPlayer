import Foundation
import Network
import Darwin

/// Состояние сервера для интерфейса.
struct WiFiServerStatus: Sendable, Equatable {
    var isRunning = false
    var port: UInt16 = 0
    var pin = ""
    var error: String?
}

/// Встроенный HTTP-сервер для передачи музыки с компьютера по Wi-Fi.
///
/// Браузер загружает каждый файл отдельным запросом `PUT /upload?path=&name=`,
/// тело запроса — сам файл; сервер пишет его на диск кусками (без загрузки в память).
/// Все запросы, кроме страницы, требуют 4-значный PIN в заголовке `X-PIN`.
/// Вся работа идёт на собственной очереди, наружу — через колбэки.
final class WiFiTransferServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "playmydisk.wifi")
    private var listener: NWListener?
    private var pin = ""
    private var port: UInt16 = 0
    private var candidatePorts: [UInt16] = []

    /// Изменилось состояние (запущен, порт, ошибка). Вызывается с очереди сервера.
    var onStatus: (@Sendable (WiFiServerStatus) -> Void)?
    /// Файл принят: относительный путь в библиотеке. Вызывается с очереди сервера.
    var onFileReceived: (@Sendable (String) -> Void)?

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            pin = String(format: "%04d", Int.random(in: 0...9999))
            candidatePorts = Array(8080...8090)
            tryNextPort()
        }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
            port = 0
            publish(running: false, error: nil)
        }
    }

    // MARK: - Запуск

    private func tryNextPort() {
        guard !candidatePorts.isEmpty else {
            publish(running: false, error: "Не удалось открыть порт 8080–8090")
            return
        }
        let next = candidatePorts.removeFirst()
        guard let nwPort = NWEndpoint.Port(rawValue: next) else {
            tryNextPort()
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: parameters, on: nwPort)
            newListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.port = next
                    AppLogger.shared.log("wifi", "Сервер запущен на порту \(next)")
                    self.publish(running: true, error: nil)
                case .failed(let error):
                    AppLogger.shared.log("wifi", "Порт \(next) недоступен: \(error.localizedDescription)")
                    newListener.cancel()
                    if self.listener === newListener {
                        self.listener = nil
                        self.tryNextPort()
                    }
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            tryNextPort()
        }
    }

    private func publish(running: Bool, error: String?) {
        let status = WiFiServerStatus(isRunning: running, port: port, pin: pin, error: error)
        onStatus?(status)
    }

    // MARK: - Соединение

    private func accept(_ connection: NWConnection) {
        let session = HTTPSession(connection: connection, server: self)
        connection.start(queue: queue)
        session.readHeader()
    }

    fileprivate var currentPIN: String { pin }

    fileprivate func fileReceived(_ relativePath: String) {
        AppLogger.shared.log("wifi", "Принят файл: \(relativePath)")
        onFileReceived?(relativePath)
    }

    // MARK: - Адрес

    /// IPv4-адрес iPhone в сети Wi-Fi (интерфейс en0) или nil.
    static func wifiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        address = String(decoding: bytes, as: UTF8.self)
                    }
                }
            }
            pointer = interface.ifa_next
        }
        return address
    }
}

// MARK: - Один HTTP-запрос

/// Обработка одного соединения: чтение заголовков, затем ответ или приём файла.
/// Все методы вызываются на очереди сервера.
private final class HTTPSession: @unchecked Sendable {
    private let connection: NWConnection
    private weak var server: WiFiTransferServer?
    private var buffer = Data()

    // Приём файла
    private var output: FileHandle?
    private var partURL: URL?
    private var finalFolder = ""
    private var finalName = ""
    private var remaining = 0

    private static let maxHeader = 16 * 1024

    init(connection: NWConnection, server: WiFiTransferServer) {
        self.connection = connection
        self.server = server
    }

    func readHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                let rest = buffer.subdata(in: range.upperBound..<buffer.endIndex)
                buffer = Data()
                handle(header: String(decoding: headerData, as: UTF8.self), body: rest)
                return
            }
            if error != nil || isComplete || buffer.count > Self.maxHeader {
                connection.cancel()
                return
            }
            readHeader()
        }
    }

    private func handle(header: String, body: Data) {
        let lines = header.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else {
            respond(400, text: "Bad Request")
            return
        }
        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let components = URLComponents(string: "http://local" + target)
        let path = components?.path ?? "/"
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        if method == "GET" && (path == "/" || path == "/index.html") {
            respond(200, contentType: "text/html; charset=utf-8", body: Data(WebUploadPage.html.utf8))
            return
        }

        guard let server, headers["x-pin"] == server.currentPIN else {
            respond(401, text: "PIN")
            return
        }

        switch (method, path) {
        case ("GET", "/folders"):
            let folders = ["" ] + Self.allFolders()
            let json = (try? JSONEncoder().encode(folders)) ?? Data("[]".utf8)
            respond(200, contentType: "application/json; charset=utf-8", body: json)
        case ("PUT", "/upload"):
            startUpload(query: query, headers: headers, initialBody: body)
        default:
            respond(404, text: "Not Found")
        }
    }

    // MARK: - Приём файла

    private func startUpload(query: [String: String], headers: [String: String], initialBody: Data) {
        let name = (query["name"] ?? "").replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
        var folder = (query["path"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if folder.contains("..") { folder = "" }
        guard !name.isEmpty, !name.hasPrefix("."), AudioFormats.isSupported(URL(fileURLWithPath: name)) else {
            respond(415, text: "Unsupported file type")
            return
        }
        guard let lengthText = headers["content-length"], let length = Int(lengthText), length > 0 else {
            respond(411, text: "Length Required")
            return
        }

        let fm = FileManager.default
        let dir = LibraryPaths.url(forRelative: folder)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            respond(500, text: "Cannot create folder")
            return
        }
        let part = dir.appendingPathComponent(".\(UUID().uuidString).part")
        fm.createFile(atPath: part.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: part) else {
            respond(500, text: "Cannot write")
            return
        }
        output = handle
        partURL = part
        finalFolder = folder
        finalName = name
        remaining = length

        if !initialBody.isEmpty {
            write(initialBody.prefix(remaining))
        }
        if remaining <= 0 {
            finishUpload()
        } else {
            readBody()
        }
    }

    private func readBody() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                write(data.prefix(remaining))
            }
            if remaining <= 0 {
                finishUpload()
                return
            }
            if error != nil || isComplete {
                abortUpload()
                return
            }
            readBody()
        }
    }

    private func write(_ data: Data) {
        do {
            try output?.write(contentsOf: data)
            remaining -= data.count
        } catch {
            abortUpload()
        }
    }

    private func finishUpload() {
        try? output?.close()
        output = nil
        guard let partURL else {
            respond(500, text: "Error")
            return
        }
        let name = LibraryPaths.uniqueName(for: finalName, inFolder: finalFolder)
        let target = LibraryPaths.url(forRelative: finalFolder).appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: partURL, to: target)
            server?.fileReceived(LibraryPaths.join(finalFolder, name))
            respond(200, text: "OK")
        } catch {
            try? FileManager.default.removeItem(at: partURL)
            respond(500, text: "Cannot save")
        }
        self.partURL = nil
    }

    private func abortUpload() {
        try? output?.close()
        output = nil
        if let partURL {
            try? FileManager.default.removeItem(at: partURL)
        }
        partURL = nil
        connection.cancel()
    }

    // MARK: - Ответ

    private func respond(_ code: Int, text: String) {
        respond(code, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    private func respond(_ code: Int, contentType: String, body: Data) {
        let reason: String
        switch code {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 411: reason = "Length Required"
        case 415: reason = "Unsupported Media Type"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        let packet = Data(head.utf8) + body
        connection.send(content: packet, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }

    /// Все папки библиотеки (относительные пути).
    private static func allFolders() -> [String] {
        var result: [String] = []
        var stack = [""]
        while let folder = stack.popLast() {
            for name in LibraryScanner.subfolders(of: folder) {
                let full = LibraryPaths.join(folder, name)
                result.append(full)
                stack.append(full)
            }
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
