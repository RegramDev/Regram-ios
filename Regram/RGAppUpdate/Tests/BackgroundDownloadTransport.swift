// MARK: Regram — deterministic URLSession boundary for the production persistent download manager.
import Foundation

protocol URLSessionDownloadDelegate: AnyObject {}
final class URLSessionConfiguration {
    var sessionSendsLaunchEvents = false
    var isDiscretionary = true
    var waitsForConnectivity = false
    var timeoutIntervalForRequest: Double = 0
    var timeoutIntervalForResource: Double = 0
    var httpCookieStorage: HTTPCookieStorage?
    var urlCredentialStorage: URLCredentialStorage?
    static func background(withIdentifier: String) -> URLSessionConfiguration { URLSessionConfiguration() }
}
class URLSessionTask {
    let taskIdentifier: Int
    var originalRequest: URLRequest?
    var taskDescription: String?
    var response: URLResponse?
    var countOfBytesReceived: Int64 = 0
    var cancelled = false
    var resumed = false
    init(url: URL, identifier: Int) { originalRequest = URLRequest(url: url); taskIdentifier = identifier }
    func cancel() { cancelled = true }
    func resume() { resumed = true }
}
final class URLSessionDownloadTask: URLSessionTask {}
final class URLSession {
    static var current: URLSession!
    static var recoveredTasks: [URLSessionTask] = []
    var tasks: [URLSessionTask] = []
    var holdEnumeration = false
    var enumeration: (([URLSessionTask]) -> Void)?
    init(configuration: URLSessionConfiguration, delegate: AnyObject, delegateQueue: OperationQueue?) {
        tasks = Self.recoveredTasks; Self.recoveredTasks = []; Self.current = self
    }
    func getAllTasks(completionHandler: @escaping ([URLSessionTask]) -> Void) {
        if holdEnumeration { enumeration = completionHandler } else { completionHandler(tasks) }
    }
    func downloadTask(with url: URL) -> URLSessionDownloadTask {
        let task = URLSessionDownloadTask(url: url, identifier: tasks.count + 1); tasks.append(task); return task
    }
}
