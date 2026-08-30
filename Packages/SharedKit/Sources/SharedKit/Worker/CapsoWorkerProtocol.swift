// Packages/SharedKit/Sources/SharedKit/Worker/CapsoWorkerProtocol.swift
import Foundation

@objc public protocol CapsoWorkerOCRProtocol {
    func recognizeText(
        imageData: Data,
        keepLineBreaks: Bool,
        languages: [String]?,
        with reply: @escaping (String?, Error?) -> Void
    )
}

@objc public protocol CapsoWorkerExportProtocol {
    func exportVideo(
        sourceURL: URL,
        format: String,
        quality: String,
        destinationURL: URL?,
        with reply: @escaping (URL?, Error?) -> Void
    )
}

@objc public protocol CapsoWorkerProtocol: CapsoWorkerOCRProtocol, CapsoWorkerExportProtocol {}

/// Client bridge for communicating with the on-demand Capso worker service.
public final class CapsoWorkerClient: @unchecked Sendable {
    public static let shared = CapsoWorkerClient()
    private let connectionLock = NSLock()
    private var xpcConnection: NSXPCConnection?

    private init() {}

    public func makeConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = xpcConnection {
            return existing
        }

        let connection = NSXPCConnection(serviceName: "com.awesomemacapps.CapsoWorker")
        connection.remoteObjectInterface = NSXPCInterface(with: CapsoWorkerProtocol.self)
        connection.interruptionHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.invalidationHandler = { [weak self] in
            self?.invalidateConnection()
        }
        connection.resume()
        xpcConnection = connection
        return connection
    }

    public func invalidateConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        xpcConnection?.invalidate()
        xpcConnection = nil
    }
}
