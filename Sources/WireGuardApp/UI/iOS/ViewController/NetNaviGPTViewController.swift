//
// Copyright © 2025 Freecomm. All Rights Reserved.

import UIKit

class NetNaviGPTViewController: UIViewController {

    private let tableView = UITableView()
    private let messageInputBar = UIView()
    private let textField = UITextField()
    private let sendButton = UIButton(type: .system)

    // Simple data model for the chat
    private var messages: [(text: String, isUser: Bool)] = [
        ("Hello! I am NetNavi GPT. How can I help you today?", false)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
    }

    private func setupUI() {
        title = "NetNaviGPT"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissVC))

        // TableView setup
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)

        // Input Bar setup (Liquid Glass style for 2026)
        messageInputBar.backgroundColor = .secondarySystemBackground
        view.addSubview(messageInputBar)

        textField.placeholder = "Message NetNavi..."
        textField.borderStyle = .roundedRect
        textField.backgroundColor = .tertiarySystemBackground
        messageInputBar.addSubview(textField)

        sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        sendButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
        messageInputBar.addSubview(sendButton)
    }

    private func setupConstraints() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        messageInputBar.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // Table view constraints
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: messageInputBar.topAnchor),

            // Input bar constraints (pinned to keyboard/bottom)
            messageInputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            messageInputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            messageInputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            messageInputBar.heightAnchor.constraint(equalToConstant: 60),

            // Textfield & Button
            textField.leadingAnchor.constraint(equalTo: messageInputBar.leadingAnchor, constant: 16),
            textField.centerYAnchor.constraint(equalTo: messageInputBar.centerYAnchor),
            textField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),

            sendButton.trailingAnchor.constraint(equalTo: messageInputBar.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: messageInputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func sendMessage() {
        guard let text = textField.text, !text.isEmpty else { return }

        // Append user message
        messages.append((text: text, isUser: true))
        textField.text = ""
        tableView.reloadData()
        scrollToBottom()

        // Mock GPT Response
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.messages.append((text: "Coming soon...", false))
            self.tableView.reloadData()
            self.scrollToBottom()
        }
    }

    @objc private func dismissVC() {
        dismiss(animated: true)
    }

    private func scrollToBottom() {
        let indexPath = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
    }
}

// MARK: - TableView Extensions
extension NetNaviGPTViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let message = messages[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = message.text
        content.secondaryText = message.isUser ? "You" : "NetNaviGPT"

        // 2026 styling: Use different background colors for bubbles
        cell.contentConfiguration = content
        cell.backgroundColor = message.isUser ? .systemBlue.withAlphaComponent(0.1) : .clear

        return cell
    }
}

