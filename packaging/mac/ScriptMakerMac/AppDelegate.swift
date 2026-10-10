import Cocoa

/// Launcher for the Script Maker thin client.
///
/// The UI itself is Streamlit (bundled under Resources/streamlit-payload).
/// On launch this app starts the Streamlit server and opens it in the
/// default browser. The pipeline server URL is configured inside the UI
/// (defaults to http://localhost:8000).
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var serverTask: Process?
    private let uiPort = 8502

    func applicationDidFinishLaunching(_ notification: Notification) {
        startStreamlit()
        // Give the server a moment, then open the UI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if let url = URL(string: "http://localhost:\(self.uiPort)") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        serverTask?.terminate()
    }

    private func startStreamlit() {
        guard let payload = Bundle.main.url(forResource: "streamlit-payload", withExtension: nil) else {
            fatalError("Script Maker: streamlit-payload missing from app Resources.")
        }
        let task = Process()
        task.executableURL = payload.appendingPathComponent("launch.sh")
        task.arguments = ["\(uiPort)"]
        task.currentDirectoryURL = payload
        do {
            try task.run()
            serverTask = task
        } catch {
            fatalError("Script Maker: could not start Streamlit server: \(error)")
        }
    }
}
