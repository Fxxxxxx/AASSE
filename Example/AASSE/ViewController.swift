import UIKit
import AASSE

class ViewController: UIViewController {
    private let textView = UITextView()
    private var observationTask: Task<Void, Never>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        connectToSSE()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .darkText
        view.addSubview(textView)
        
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        appendMessage("AASSE SSE Client Demo\n\n")
    }
    
    private func connectToSSE() {
        guard let url = URL(string: "https://api.example.com/sse") else {
            appendMessage("❌ Invalid URL\n")
            return
        }
        
        let configuration = AASSEClient.Configuration(
            url: url,
            headers: ["Authorization": "Bearer token"],
            retryInterval: 3,
            maxRetryCount: 5
        )
        
        let client = AASSEClient(configuration: configuration)
        
        observationTask = Task {
            for await event in client.connect() {
                handleEvent(event)
            }
        }
    }
    
    private func handleEvent(_ event: AASSEClientEvent) {
        switch event {
        case .open:
            appendMessage("✅ Connection opened\n")
            
        case .event(let sseEvent):
            switch sseEvent {
            case .message(let id, let eventType, let data):
                appendMessage("📨 Message:")
                if let id {
                    appendMessage("  ID: \(id)")
                }
                if let eventType {
                    appendMessage("  Event: \(eventType)")
                }
                appendMessage("  Data: \(data)\n")
                
            case .retry(let interval):
                appendMessage("⏱️ Server retry interval: \(interval)s\n")
            }
            
        case .error(let error):
            appendMessage("❌ Error: \(error.localizedDescription)\n")
            
        case .closed:
            appendMessage("🔌 Connection closed\n")
        }
    }
    
    private func appendMessage(_ message: String) {
        DispatchQueue.main.async {
            self.textView.text += message
            let range = NSRange(location: self.textView.text.count - 1, length: 1)
            self.textView.scrollRangeToVisible(range)
        }
    }
    
    deinit {
        observationTask?.cancel()
    }
}
