//
// In-App Purchase/Subscription helper for macOS (AppKit)
//
//

import AppKit
import StoreKit

// MD5 utilities
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

@MainActor
final class SubscriptionPurchaseController: NSObject {
    static let shared = SubscriptionPurchaseController()

    private let productIDs: Set<String> = [
        "co.freecomm.netnavi.premium.monthly"
    ]

    private var products: [Product] = []

    // Purchase window
    private var window: NSWindow?

    // MARK: - Public API

    func showPurchaseWindow() {
        if window == nil {
            let vc = PurchaseViewController(purchaseHandler: self)
            let window = NSWindow(contentViewController: vc)
            window.title = "NetNavi Premium Subscriptions"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            self.window = window
        }

        Task { [weak self] in
            guard let self else { return }
            await self.loadProducts()

            if let vc = self.window?.contentViewController as? PurchaseViewController {
                vc.update(with: self.products)
            }

            if let window = self.window, let contentView = window.contentView {
                // 1. Force the Auto Layout pass on the components
                contentView.layoutSubtreeIfNeeded()

                // 2. Extract the exact bounding rectangle required by your constraints
                let fittingSize = contentView.fittingSize

                // 3. Directly clamp the window dimensions to this tight bounding wrapper
                var frame = window.frame
                let contentRect = window.contentRect(forFrameRect: frame)

                let deltaHeight = fittingSize.height - contentRect.height
                frame.size.height += deltaHeight
                frame.origin.y -= deltaHeight
                frame.size.width = 420

                window.setFrame(frame, display: true, animate: false)
            }

            self.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - StoreKit

    private func loadProducts() async {
        do {
            let storeProducts = try await Product.products(for: Array(productIDs))
            // Sort subscriptions by price ascending for display
            self.products = storeProducts.sorted(by: { $0.displayPrice < $1.displayPrice })
        } catch {
            self.products = []
            debugPrint("Failed to load products: \(error)")
        }
    }

    // MARK: - Backend Management Integration Helper

    private final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
        // This is the SESSION-level method. Notice it does NOT have a 'task:' parameter.
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private struct BackendPurchasePayload {
        let deviceToken: String
        let transactionID: String
        let originalTransactionID: String
        let productID: String
        let subscriptionGroupID: String
        let purchaseTimeMillis: Int64
        let expiresTimeMillis: Int64
        let environment: String
        let currency: String
        let amount: Double
        let signedTransactionInfo: String?
        let signedRenewalInfo: String?
    }

    private func notifyBackendOfPurchase(_ payload: BackendPurchasePayload) async throws {
        guard let url = URL(string: "https://103.47.27.44:9443/subscription/ios/paid") else {
            throw NSError(domain: "Network", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid backend server URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Build auth headers
        let timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
        let nonce = UUID().uuidString
        let signatureSource = payload.deviceToken + String(timestamp) + nonce
        let signature = Self.md5(signatureSource)

        request.setValue(payload.deviceToken, forHTTPHeaderField: "Authorization")
        request.setValue(String(timestamp), forHTTPHeaderField: "Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "Nonce")
        request.setValue(signature, forHTTPHeaderField: "Signature")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Prepare JSON request packet data
        var bodyData: [String: Any] = [
            "transaction_id": payload.transactionID,
            "original_transaction_id": payload.originalTransactionID,
            "product_id": payload.productID,
            "subscription_group_id": payload.subscriptionGroupID,
            "purchase_time": payload.purchaseTimeMillis,
            "expires_time": payload.expiresTimeMillis,
            "environment": payload.environment,
            "currency": payload.currency,
            "amount": payload.amount
        ]

        if let signedTransactionInfo = payload.signedTransactionInfo {
            bodyData["signed_transaction_info"] = signedTransactionInfo
        }
        if let signedRenewalInfo = payload.signedRenewalInfo {
            bodyData["signed_renewal_info"] = signedRenewalInfo
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyData, options: [])

        // Instantiate local session
        let session = URLSession(configuration: .default, delegate: InsecureSessionDelegate(), delegateQueue: nil)

        // Use a defer block to guarantee that the session breaks its strong delegate reference
        // and gets deallocated from memory immediately when this function scope exits.
        defer {
            session.invalidateAndCancel()
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "Network", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid server communication infrastructure"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage = String(data: data, encoding: .utf8) ?? "No message"
            throw NSError(domain: "Network", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Backend rejection (\(httpResponse.statusCode)): \(serverMessage)"])
        }
    }


    func netnaviPurchase(_ product: Product, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            do {
                // Apple native StoreKit framework
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .unverified(_, let error):
                        completion(.failure(error))

                    case .verified(let transaction):
                        let rawJWSToken = verification.jwsRepresentation

                        do {
                            // Map StoreKit transaction fields to backend payload. Adjust mappings as needed.
                            let environment = (try? await AppStore.sync()) != nil ? "Production" : "Production" // set appropriately if you distinguish Sandbox
                            let purchaseMillis = Int64(transaction.purchaseDate.timeIntervalSince1970 * 1000)
                            let expiresMillis = Int64((transaction.expirationDate ?? Date()).timeIntervalSince1970 * 1000)
                            /* TODO: enable later
                            let payload = BackendPurchasePayload(
                                deviceToken: DeviceUUID.get(), // device_uuid
                                transactionID: "\(transaction.id)",
                                originalTransactionID: "\(transaction.originalID)",
                                productID: product.id,
                                subscriptionGroupID: product.subscription?.subscriptionGroupID ?? "",
                                purchaseTimeMillis: purchaseMillis,
                                expiresTimeMillis: expiresMillis,
                                environment: environment,
                                currency: product.priceFormatStyle.currencyCode ?? Locale.current.currency?.identifier ?? "USD",
                                amount: (try? Decimal(string: product.displayPrice.replacingOccurrences(of: ",", with: "."))).map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0.0,
                                signedTransactionInfo: rawJWSToken,
                                signedRenewalInfo: nil
                            )
                            try await notifyBackendOfPurchase(payload)
                             */

                            // customer has been changed. TODO: Global handler for async?
                            await transaction.finish()
                            completion(.success(()))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                case .userCancelled:
                    completion(.failure(NSError(domain: "IAP", code: NSUserCancelledError, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
                case .pending:
                    completion(.failure(NSError(domain: "IAP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Purchase pending"])))
                @unknown default:
                    completion(.failure(NSError(domain: "IAP", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown result"])))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

    private static func md5(_ string: String) -> String {
        // Compute MD5 hex digest
        guard let data = string.data(using: .utf8) else { return "" }
        #if canImport(CryptoKit)
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
        #else
        // Fallback simple implementation using CommonCrypto if available
        // Note: If CommonCrypto is not linked, adjust project settings accordingly.
        return data.withUnsafeBytes { (rawBufferPtr: UnsafeRawBufferPointer) -> String in
            #if canImport(CommonCrypto)
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(rawBufferPtr.baseAddress, CC_LONG(data.count), &hash)
            return hash.map { String(format: "%02x", $0) }.joined()
            #else
            // As a last resort, return empty string to avoid crash
            return ""
            #endif
        }
        #endif
    }
}

// MARK: - Purchase UI

@MainActor
private final class PurchaseViewController: NSViewController {
    private let purchaseHandler: SubscriptionPurchaseController
    private var products: [Product] = []

    // UI
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let buyButton: NSButton = {
        let b = NSButton(title: "Subscribe", target: nil, action: nil)
        b.bezelStyle = .rounded
        b.isEnabled = false
        return b
    }()
    private let statusLabel: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        return l
    }()

    private var selectedIndex: Int? {
        didSet { buyButton.isEnabled = selectedIndex != nil }
    }

    init(purchaseHandler: SubscriptionPurchaseController) {
        self.purchaseHandler = purchaseHandler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = NSView()
        setupUI()
    }

    func update(with products: [Product]) {
        self.products = products
        tableView.reloadData()
        if !products.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        view.layoutSubtreeIfNeeded()
        statusLabel.stringValue = products.isEmpty ? "No products available. Check configuration." : ""
    }

    private func setupUI() {
        // Configure table
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("product"))
        column.title = "Products"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsEmptySelection = false

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        tableView.rowHeight = 24

        let bottomConstraint = statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        bottomConstraint.priority = .defaultHigh

        // Layout
        [scrollView, buyButton, statusLabel].forEach { v in
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        buyButton.target = self
        buyButton.action = #selector(buyTapped)

        NSLayoutConstraint.activate([

            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            buyButton.topAnchor.constraint(greaterThanOrEqualTo: scrollView.bottomAnchor, constant: 12),
            buyButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            scrollView.bottomAnchor.constraint(equalTo: buyButton.topAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: buyButton.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            bottomConstraint
        ])

        let minScrollHeight = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        minScrollHeight.priority = .defaultHigh
        minScrollHeight.isActive = true
    }

    @objc private func buyTapped() {
        guard let index = selectedIndex, products.indices.contains(index) else { return }
        let product = products[index]
        statusLabel.stringValue = "Purchasing \(product.displayName)…"
        buyButton.isEnabled = false
        purchaseHandler.netnaviPurchase(product) { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success:
                    self?.statusLabel.stringValue = "Purchase successful!"
                case .failure(let error):
                    self?.statusLabel.stringValue = "Purchase failed: \(error.localizedDescription)"
                }
                self?.buyButton.isEnabled = true
            }
        }
    }
}

extension PurchaseViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { products.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let view: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            view = reused
        } else {
            view = NSTableCellView()
            view.identifier = id
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(text)
            view.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
                text.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
                text.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
            ])
        }
        if products.indices.contains(row) {
            let p = products[row]
            var period = ""
            if let info = p.subscription {
                let sp = info.subscriptionPeriod
                period = sp.unit.localizedDescription(count: sp.value)
            }
            view.textField?.stringValue = [p.displayName, p.displayPrice, period].filter { !$0.isEmpty }.joined(separator: " • ")
        }
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedIndex = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
    }
}

private extension Product.SubscriptionPeriod.Unit {
    func localizedDescription(count: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        switch self {
        case .day: formatter.allowedUnits = [.day]
        case .week: formatter.allowedUnits = [.weekOfMonth]
        case .month: formatter.allowedUnits = [.month]
        case .year: formatter.allowedUnits = [.year]
        @unknown default: formatter.allowedUnits = []
        }
        return formatter.string(from: DateComponents(value: count, for: self)) ?? ""
    }
}

private extension DateComponents {
    init(value: Int, for unit: Product.SubscriptionPeriod.Unit) {
        switch unit {
        case .day: self.init(day: value)
        case .week: self.init(weekOfMonth: value)
        case .month: self.init(month: value)
        case .year: self.init(year: value)
        @unknown default: self.init()
        }
    }
}

