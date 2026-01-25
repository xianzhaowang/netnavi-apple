//
// Copyright © 2025 Freecomm. All Rights Reserved.

import UIKit
import MobileCoreServices
import UserNotifications

class TunnelsListTableViewController: UIViewController {

    var tunnelsManager: TunnelsManager?

    enum TableState: Equatable {
        case normal
        case rowSwiped
        case multiSelect(selectionCount: Int)
    }

    // NetNavi Service Details
    enum Row {
        case tunnel(TunnelContainer)
        case detail(TunnelContainer)
    }

    private var rows: [Row] = []

    let tableView: UITableView = {
        let tableView = UITableView(frame: CGRect.zero, style: .plain)
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.register(TunnelListCell.self)
        tableView.register(NetNaviAgentDetailInlineCell.self)
        return tableView
    }()

    let centeredAddButton: BorderedTextButton = {
        let button = BorderedTextButton()
        button.title = tr("tunnelsListCenteredAddTunnelButtonTitle")
        button.isHidden = true
        return button
    }()

    let centeredMessageLabel: UILabel = {
        let label = UILabel()
        label.text = "please stay tuned…"
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    let busyIndicator: UIActivityIndicatorView = {
        let busyIndicator: UIActivityIndicatorView
        busyIndicator = UIActivityIndicatorView(style: .medium)
        busyIndicator.hidesWhenStopped = true
        return busyIndicator
    }()

    var detailDisplayedTunnel: TunnelContainer?
    var tableState: TableState = .normal {
        didSet {
            handleTableStateChange()
        }
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .systemBackground

        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        view.addSubview(busyIndicator)
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            busyIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            busyIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        view.addSubview(centeredAddButton)
        centeredAddButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            centeredAddButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centeredAddButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        view.addSubview(centeredMessageLabel)
        centeredMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            centeredMessageLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            centeredMessageLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            centeredMessageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            centeredMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16)
        ])

        centeredAddButton.onTapped = { [weak self] in
            guard let self = self else { return }
            self.addButtonTapped(sender: self.centeredAddButton)
        }

        busyIndicator.startAnimating()
        configureFooter()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableState = .normal
        restorationIdentifier = "TunnelsListVC"
    }

    private var footerView: NetNaviFooterView!

    private func configureFooter() {
        footerView = NetNaviFooterView(
            primaryAction: { [weak self] in self?.footerGPTTapped() },
            portalAction: { [weak self] in self?.footerPortalTapped() },
            settingsAction: { [weak self] in self?.footerSettingsTapped() }
        )

        view.addSubview(footerView)
        footerView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 100)
        ])

        footerView.attach(to: tableView)
    }

    /*
    private func configureFooter() {
        // Container that extends under the safe area to fill the bottom curve
        let container = UIView()
        container.backgroundColor = .clear
        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false

        // Read safe area bottom inset at layout time
        let safeBottom = view.safeAreaInsets.bottom
        let baseHeight: CGFloat = 100
        let totalHeight = baseHeight + safeBottom

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: totalHeight)
        ])

        // Rounded background that matches the top curve, flush at the bottom
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        background.backgroundColor = .clear
        background.layer.cornerRadius = 0
        background.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true

        // Optional shadow to emphasize floating look
        background.layer.shadowColor = UIColor.black.cgColor
        background.layer.shadowOpacity = 0.15
        background.layer.shadowOffset = CGSize(width: 0, height: -3)
        background.layer.shadowRadius = 12

        container.addSubview(background)
        background.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            background.topAnchor.constraint(equalTo: container.topAnchor),
            background.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        // Settings button centered, lifted above the home indicator
        let settingsButton = UIButton(type: .system)
        settingsButton.setTitle(tr("tunnelsListSettingsButtonTitle"), for: .normal)
        settingsButton.addTarget(self, action: #selector(footerSettingsTapped), for: .touchUpInside)
        settingsButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "headphones")
            config.imagePlacement = .top
            config.imagePadding = 6
            config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            config.baseForegroundColor = .label
            settingsButton.configuration = config
        } else {
            if let image = UIImage(systemName: "headphones") {
                settingsButton.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
                settingsButton.tintColor = .label
                settingsButton.setTitleColor(.label, for: .normal)
                // Approximate vertical stacking for pre-iOS 15
                let titleHeight = settingsButton.titleLabel?.intrinsicContentSize.height ?? 0
                let imageWidth = image.size.width
                let titleWidth = settingsButton.titleLabel?.intrinsicContentSize.width ?? 0
                settingsButton.titleEdgeInsets = UIEdgeInsets(top: 6, left: -imageWidth, bottom: -6, right: 0)
                settingsButton.imageEdgeInsets = UIEdgeInsets(top: -titleHeight, left: 0, bottom: 0, right: -titleWidth)
                settingsButton.contentHorizontalAlignment = .center
                settingsButton.contentVerticalAlignment = .center
            }
        }
        background.contentView.addSubview(settingsButton)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        let portalButton = UIButton(type: .system)
        let portalTitle = (NSLocalizedString("tunnelsListPortalButtonTitle", comment: "") != "tunnelsListPortalButtonTitle") ? tr("tunnelsListPortalButtonTitle") : "Me"
        portalButton.setTitle(portalTitle, for: .normal)
        portalButton.addTarget(self, action: #selector(footerPortalTapped), for: .touchUpInside)
        portalButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        if #available(iOS 15.0, *) {
            var pconfig = UIButton.Configuration.plain()
            pconfig.image = UIImage(systemName: "person")
            pconfig.imagePlacement = .top
            pconfig.imagePadding = 6
            pconfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            pconfig.baseForegroundColor = .label
            portalButton.configuration = pconfig
        } else {
            if let image = UIImage(systemName: "person") {
                portalButton.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
                portalButton.tintColor = .label
                portalButton.setTitleColor(.label, for: .normal)
                let titleHeight = portalButton.titleLabel?.intrinsicContentSize.height ?? 0
                let imageWidth = image.size.width
                let titleWidth = portalButton.titleLabel?.intrinsicContentSize.width ?? 0
                portalButton.titleEdgeInsets = UIEdgeInsets(top: 6, left: -imageWidth, bottom: -6, right: 0)
                portalButton.imageEdgeInsets = UIEdgeInsets(top: -titleHeight, left: 0, bottom: 0, right: -titleWidth)
                portalButton.contentHorizontalAlignment = .center
                portalButton.contentVerticalAlignment = .center
            }
        }
        background.contentView.addSubview(portalButton)
        portalButton.translatesAutoresizingMaskIntoConstraints = false

        let gptButton = UIButton(type: .system)
        let gptTitle = "NetNaviGPT"
        gptButton.setTitle(gptTitle, for: .normal)
        gptButton.addTarget(self, action: #selector(footerGPTTapped), for: .touchUpInside)
        let customFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        // gptButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        gptButton.titleLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: customFont)
        gptButton.titleLabel?.adjustsFontForContentSizeCategory = true
        if #available(iOS 15.0, *) {
            var gconfig = UIButton.Configuration.plain()
            gconfig.image = UIImage(systemName: "bubble.left.and.bubble.right")
            gconfig.imagePlacement = .top
            gconfig.imagePadding = 6
            gconfig.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            gconfig.baseForegroundColor = .label
            gptButton.configuration = gconfig
        } else {
            if let image = UIImage(systemName: "bubble.left.and.bubble.right") {
                gptButton.setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
                gptButton.tintColor = .label
                gptButton.setTitleColor(.label, for: .normal)
                let titleHeight = gptButton.titleLabel?.intrinsicContentSize.height ?? 0
                let imageWidth = image.size.width
                let titleWidth = gptButton.titleLabel?.intrinsicContentSize.width ?? 0
                gptButton.titleEdgeInsets = UIEdgeInsets(top: 6, left: -imageWidth, bottom: -6, right: 0)
                gptButton.imageEdgeInsets = UIEdgeInsets(top: -titleHeight, left: 0, bottom: 0, right: -titleWidth)
                gptButton.contentHorizontalAlignment = .center
                gptButton.contentVerticalAlignment = .center
            }
        }
        background.contentView.addSubview(gptButton)
        gptButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            settingsButton.centerYAnchor.constraint(equalTo: background.topAnchor, constant: baseHeight / 2),
            portalButton.centerYAnchor.constraint(equalTo: background.topAnchor, constant: baseHeight / 2),
            gptButton.centerYAnchor.constraint(equalTo: background.topAnchor, constant: baseHeight / 2),

            // Horizontal layout: [gpt] 24 [portal] 24 [settings], centered as a group
            portalButton.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            gptButton.trailingAnchor.constraint(equalTo: portalButton.leadingAnchor, constant: -24),
            settingsButton.leadingAnchor.constraint(equalTo: portalButton.trailingAnchor, constant: 24)
        ])

        // Ensure table content is not hidden behind the footer
        let extraBottomInset: CGFloat = 24
        var inset = tableView.contentInset
        inset.bottom = max(inset.bottom, totalHeight + extraBottomInset)
        tableView.contentInset = inset
        tableView.scrollIndicatorInsets = inset
    }
    */

    @objc private func footerSettingsTapped() {
        openSettings()
    }

    @objc private func footerPortalTapped() {
        let deviceUUID = DeviceUUID.get()
        print("Device UUID:", deviceUUID)
        guard let url = URL(string: "https://my.netnavi.io/login?deviceToken=\(deviceUUID)") else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc private func footerGPTTapped() {
        let chatVC = NetNaviGPTViewController()
        let nav = UINavigationController(rootViewController: chatVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func openSettings() {
        guard tunnelsManager != nil else { return }
        let settingsVC = SettingsTableViewController(tunnelsManager: tunnelsManager)
        let settingsNC = UINavigationController(rootViewController: settingsVC)
        settingsNC.modalPresentationStyle = .formSheet
        present(settingsNC, animated: true)
    }

    func showWaitingMessage(_ show: Bool, message: String = "please stay tuned…") {
        centeredMessageLabel.text = message
        centeredMessageLabel.isHidden = !show
        centeredAddButton.isHidden = true
    }

    private func startRegistration() {
        guard let url = URL(string: "https://netnavi.io/api/register") else { return }
        // Show inline waiting message
        showWaitingMessage(true, message: "In progress, please stay tuned…")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "device": UIDevice.current.name,
            "platform": "iOS",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    // Optionally show an error inline or via alert
                    self.showWaitingMessage(false)
                    // You could present an alert here if desired
                    return
                }
                // On success, you might trigger a reload of tunnels if appropriate
                self.tunnelsManager?.reload()
            }
        }.resume()
    }

    func handleTableStateChange() {
        switch tableState {
        case .normal:
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped(sender:)))
            navigationItem.leftBarButtonItem = nil
        case .rowSwiped:
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneButtonTapped))
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: tr("tunnelsListSelectButtonTitle"), style: .plain, target: self, action: #selector(selectButtonTapped))
        case .multiSelect(let selectionCount):
            if selectionCount > 0 {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: tr("tunnelsListDeleteButtonTitle"), style: .plain, target: self, action: #selector(deleteButtonTapped(sender:)))
            } else {
                navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: tr("tunnelsListSelectAllButtonTitle"), style: .plain, target: self, action: #selector(selectAllButtonTapped))
            }
        }
        if case .multiSelect(let selectionCount) = tableState, selectionCount > 0 {
            navigationItem.title = tr(format: "tunnelsListSelectedTitle (%d)", selectionCount)
        } else {
            navigationItem.title = tr("tunnelsListTitle")
        }
        if case .multiSelect = tableState {
            tableView.allowsMultipleSelectionDuringEditing = true
        } else {
            tableView.allowsMultipleSelectionDuringEditing = false
        }
    }

    private func hasNetNaviAgent() -> Bool {
        guard let tunnelsManager = tunnelsManager else { return false }

        for i in 0..<tunnelsManager.numberOfTunnels() {
            if tunnelsManager.tunnel(at: i).name == "NetNavi Agent" {
                return true
            }
        }
        return false
    }

    // --- New function to rebuild rows ---
    private func rebuildRows() {
        guard let tunnelsManager = tunnelsManager else { return }

        rows.removeAll()

        // Add all tunnels
        for i in 0..<tunnelsManager.numberOfTunnels() {
            rows.append(.tunnel(tunnelsManager.tunnel(at: i)))
        }

        // Add NetNavi inline detail if there is exactly one tunnel named "NetNavi Agent"
        if tunnelsManager.numberOfTunnels() == 1 {
            let tunnel = tunnelsManager.tunnel(at: 0) // no 'if let' because it's non-optional
            if tunnel.name == "NetNavi Agent" {
                rows.append(.detail(tunnel))
            }
        }
        tableView.reloadData()

        if hasNetNaviAgent() {
            showWaitingMessage(false)
        }
    }

    func setTunnelsManager(tunnelsManager: TunnelsManager) {
        self.tunnelsManager = tunnelsManager
        tunnelsManager.tunnelsListDelegate = self

        busyIndicator.stopAnimating()
        tableView.reloadData()

        rebuildRows()

        // replaced by netnavi activation logic
        // centeredAddButton.isHidden = tunnelsManager.numberOfTunnels() > 0
        let isEmpty = tunnelsManager.numberOfTunnels() == 0
        centeredAddButton.isHidden = isEmpty ? true : false // will be controlled by showWaitingMessage
        if isEmpty {
            // Show waiting message in place of the button and start registration
            showWaitingMessage(true, message: "In progress, please stay tuned…")
            startRegistration()
        } else {
            showWaitingMessage(false)
        }

        if tunnelsManager.numberOfTunnels() == 1 {
            let tunnelName = "NetNavi Agent"
            if let tunnel = tunnelsManager.tunnel(named: tunnelName) {
                if tunnel.status == .inactive {
                    print("Start tunnel activation...2nd")
                    tunnelsManager.startActivation(of: tunnel)
                }
                print("tunnel status:", tunnel.status)
            }
        }

    }

    override func viewWillAppear(_: Bool) {
        if let selectedRowIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedRowIndexPath, animated: false)
        }
    }

    @objc func addButtonTapped(sender: AnyObject) {
        guard tunnelsManager != nil else { return }

        //let alert = UIAlertController(title: "", message: tr("addTunnelMenuHeader"), preferredStyle: .actionSheet)
        let alert = UIAlertController()
        /*
        let importFileAction = UIAlertAction(title: tr("addTunnelMenuImportFile"), style: .default) { [weak self] _ in
            self?.presentViewControllerForFileImport()
        }
        alert.addAction(importFileAction)

        let scanQRCodeAction = UIAlertAction(title: tr("addTunnelMenuQRCode"), style: .default) { [weak self] _ in
            self?.presentViewControllerForScanningQRCode()
        }
        alert.addAction(scanQRCodeAction)
        */

        let createFromScratchAction = UIAlertAction(title: tr("addTunnelMenuFromScratch"), style: .default) { [weak self] _ in
            if let self = self, let tunnelsManager = self.tunnelsManager {
                self.presentViewControllerForTunnelCreation(tunnelsManager: tunnelsManager)
            }
        }
        alert.addAction(createFromScratchAction)

        let cancelAction = UIAlertAction(title: tr("actionCancel"), style: .cancel)
        alert.addAction(cancelAction)

        if let sender = sender as? UIBarButtonItem {
            alert.popoverPresentationController?.barButtonItem = sender
        } else if let sender = sender as? UIView {
            alert.popoverPresentationController?.sourceView = sender
            alert.popoverPresentationController?.sourceRect = sender.bounds
        }
        present(alert, animated: true, completion: nil)
    }

    func presentViewControllerForTunnelCreation(tunnelsManager: TunnelsManager) {
        let editVC = TunnelEditTableViewController(tunnelsManager: tunnelsManager)
        let editNC = UINavigationController(rootViewController: editVC)
        editNC.modalPresentationStyle = .fullScreen
        present(editNC, animated: true)
    }

    func presentViewControllerForFileImport() {
        let documentTypes = ["com.wireguard.config.quick", String(kUTTypeText), String(kUTTypeZipArchive)]
        let filePicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        filePicker.delegate = self
        present(filePicker, animated: true)
    }

    func presentViewControllerForScanningQRCode() {
        let scanQRCodeVC = QRScanViewController()
        scanQRCodeVC.delegate = self
        let scanQRCodeNC = UINavigationController(rootViewController: scanQRCodeVC)
        scanQRCodeNC.modalPresentationStyle = .fullScreen
        present(scanQRCodeNC, animated: true)
    }

    @objc func selectButtonTapped() {
        let shouldCancelSwipe = tableState == .rowSwiped
        tableState = .multiSelect(selectionCount: 0)
        if shouldCancelSwipe {
            tableView.setEditing(false, animated: false)
        }
        tableView.setEditing(true, animated: true)
    }

    @objc func doneButtonTapped() {
        tableState = .normal
        tableView.setEditing(false, animated: true)
    }

    @objc func selectAllButtonTapped() {
        guard tableView.isEditing else { return }
        guard let tunnelsManager = tunnelsManager else { return }
        for index in 0 ..< tunnelsManager.numberOfTunnels() {
            tableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .none)
        }
        tableState = .multiSelect(selectionCount: tableView.indexPathsForSelectedRows?.count ?? 0)
    }

    @objc func cancelButtonTapped() {
        tableState = .normal
        tableView.setEditing(false, animated: true)
    }

    @objc func deleteButtonTapped(sender: AnyObject?) {
        guard let sender = sender as? UIBarButtonItem else { return }
        guard let tunnelsManager = tunnelsManager else { return }

        let selectedTunnelIndices = tableView.indexPathsForSelectedRows?.map { $0.row } ?? []
        let selectedTunnels = selectedTunnelIndices.compactMap { tunnelIndex in
            tunnelIndex >= 0 && tunnelIndex < tunnelsManager.numberOfTunnels() ? tunnelsManager.tunnel(at: tunnelIndex) : nil
        }
        guard !selectedTunnels.isEmpty else { return }
        let message = selectedTunnels.count == 1 ?
            tr(format: "deleteTunnelConfirmationAlertButtonMessage (%d)", selectedTunnels.count) :
            tr(format: "deleteTunnelsConfirmationAlertButtonMessage (%d)", selectedTunnels.count)
        let title = tr("deleteTunnelsConfirmationAlertButtonTitle")
        ConfirmationAlertPresenter.showConfirmationAlert(message: message, buttonTitle: title,
                                                         from: sender, presentingVC: self) { [weak self] in
            self?.tunnelsManager?.removeMultiple(tunnels: selectedTunnels) { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    ErrorPresenter.showErrorAlert(error: error, from: self)
                    return
                }
                self.tableState = .normal
                self.tableView.setEditing(false, animated: true)
            }
        }
    }

    func showTunnelDetail(for tunnel: TunnelContainer, animated: Bool) {
        guard let tunnelsManager = tunnelsManager else { return }
        guard let splitViewController = splitViewController else { return }
        guard let navController = navigationController else { return }

        let tunnelDetailVC = TunnelDetailTableViewController(tunnelsManager: tunnelsManager,
                                                             tunnel: tunnel)
        let tunnelDetailNC = UINavigationController(rootViewController: tunnelDetailVC)
        tunnelDetailNC.restorationIdentifier = "DetailNC"
        if splitViewController.isCollapsed && navController.viewControllers.count > 1 {
            navController.setViewControllers([self, tunnelDetailNC], animated: animated)
        } else {
            splitViewController.showDetailViewController(tunnelDetailNC, sender: self, animated: animated)
        }
        detailDisplayedTunnel = tunnel
        self.presentedViewController?.dismiss(animated: false, completion: nil)
    }

    func showNetNaviAgentDetail(for tunnel: TunnelContainer, animated: Bool) {
        guard let tunnelsManager = tunnelsManager else { return }
        guard let splitViewController = splitViewController else { return }
        guard let navController = navigationController else { return }

        let tunnelDetailVC = TunnelDetailTableViewController(tunnelsManager: tunnelsManager,
                                                             tunnel: tunnel)
        let tunnelDetailNC = UINavigationController(rootViewController: tunnelDetailVC)
        tunnelDetailNC.restorationIdentifier = "DetailNC"
        if splitViewController.isCollapsed && navController.viewControllers.count > 1 {
            navController.setViewControllers([self, tunnelDetailNC], animated: animated)
        } else {
            splitViewController.showDetailViewController(tunnelDetailNC, sender: self, animated: animated)
        }
        detailDisplayedTunnel = tunnel
        self.presentedViewController?.dismiss(animated: false, completion: nil)
    }
}

extension TunnelsListTableViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let tunnelsManager = tunnelsManager else { return }
        TunnelImporter.importFromFile(urls: urls, into: tunnelsManager, sourceVC: self, errorPresenterType: ErrorPresenter.self)
    }
}

extension TunnelsListTableViewController: QRScanViewControllerDelegate {
    func addScannedQRCode(tunnelConfiguration: TunnelConfiguration, qrScanViewController: QRScanViewController,
                          completionHandler: (() -> Void)?) {
        tunnelsManager?.add(tunnelConfiguration: tunnelConfiguration) { result in
            switch result {
            case .failure(let error):
                ErrorPresenter.showErrorAlert(error: error, from: qrScanViewController, onDismissal: completionHandler)
            case .success:
                completionHandler?()
            }
        }
    }
}

/*
extension TunnelsListTableViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return (tunnelsManager?.numberOfTunnels() ?? 0)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: TunnelListCell = tableView.dequeueReusableCell(for: indexPath)
        if let tunnelsManager = tunnelsManager {
            let tunnel = tunnelsManager.tunnel(at: indexPath.row)
            cell.tunnel = tunnel
            cell.onSwitchToggled = { [weak self] isOn in
                guard let self = self, let tunnelsManager = self.tunnelsManager else { return }
                if tunnel.hasOnDemandRules {
                    tunnelsManager.setOnDemandEnabled(isOn, on: tunnel) { error in
                        if error == nil && !isOn {
                            tunnelsManager.startDeactivation(of: tunnel)
                        }
                    }
                } else {
                    if isOn {
                        tunnelsManager.startActivation(of: tunnel)
                    } else {
                        tunnelsManager.startDeactivation(of: tunnel)
                    }
                }
            }
        }
        return cell
    }
}*/

// NetNavi Agent Servcie Detail
extension TunnelsListTableViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = rows[indexPath.row]

        switch row {
        case .tunnel(let tunnel):
            let cell: TunnelListCell = tableView.dequeueReusableCell(for: indexPath)
            cell.tunnel = tunnel
            cell.onSwitchToggled = { [weak self] isOn in
                guard let self = self, let tunnelsManager = self.tunnelsManager else { return }
                if tunnel.hasOnDemandRules {
                    tunnelsManager.setOnDemandEnabled(isOn, on: tunnel) { error in
                        if error == nil && !isOn { tunnelsManager.startDeactivation(of: tunnel) }
                    }
                } else {
                    if isOn { tunnelsManager.startActivation(of: tunnel) }
                    else { tunnelsManager.startDeactivation(of: tunnel) }
                }
            }
            return cell

        case .detail(let tunnel):
            /*
            let cell: NetNaviAgentDetailInlineCell = tableView.dequeueReusableCell(for: indexPath)
            cell.bind(tunnel)
            return cell
             */
            let cell: NetNaviAgentDetailInlineCell = tableView.dequeueReusableCell(for: indexPath)
            if let manager = tunnelsManager {
                cell.bind(tunnel: tunnel, manager: manager)
            }
            return cell
        }
    }
}

extension TunnelsListTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = rows[indexPath.row]
        switch row {
        case .tunnel(let tunnel):
            guard !tableView.isEditing else {
                tableState = .multiSelect(selectionCount: tableView.indexPathsForSelectedRows?.count ?? 0)
                return
            }
            showTunnelDetail(for: tunnel, animated: true)

        case .detail:
            // Inline detail is non-selectable
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    /* Comment it out by NetNavi Agent Service
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !tableView.isEditing else {
            tableState = .multiSelect(selectionCount: tableView.indexPathsForSelectedRows?.count ?? 0)
            return
        }
        guard let tunnelsManager = tunnelsManager else { return }
        let tunnel = tunnelsManager.tunnel(at: indexPath.row)
        showTunnelDetail(for: tunnel, animated: true)
    }
    */

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard !tableView.isEditing else {
            tableState = .multiSelect(selectionCount: tableView.indexPathsForSelectedRows?.count ?? 0)
            return
        }
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let deleteAction = UIContextualAction(style: .destructive, title: tr("tunnelsListSwipeDeleteButtonTitle")) { [weak self] _, _, completionHandler in
            guard let tunnelsManager = self?.tunnelsManager else { return }
            let tunnel = tunnelsManager.tunnel(at: indexPath.row)
            tunnelsManager.remove(tunnel: tunnel) { error in
                if error != nil {
                    ErrorPresenter.showErrorAlert(error: error!, from: self)
                    completionHandler(false)
                } else {
                    completionHandler(true)
                }
            }
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        if tableState == .normal {
            tableState = .rowSwiped
        }
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        if tableState == .rowSwiped {
            tableState = .normal
        }
    }
}

extension TunnelsListTableViewController: TunnelsManagerListDelegate {
    func tunnelAdded(at index: Int) { rebuildRows() }
    func tunnelModified(at index: Int) { rebuildRows() }
    func tunnelMoved(from oldIndex: Int, to newIndex: Int) { rebuildRows() }
    func tunnelRemoved(at index: Int, tunnel: TunnelContainer) { rebuildRows() }
}

/* replaced by Netnavi Agent Service Details
extension TunnelsListTableViewController: TunnelsManagerListDelegate {
    func tunnelAdded(at index: Int) {
        tableView.insertRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        centeredAddButton.isHidden = (tunnelsManager?.numberOfTunnels() ?? 0 > 0)
    }

    func tunnelModified(at index: Int) {
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
    }

    func tunnelMoved(from oldIndex: Int, to newIndex: Int) {
        tableView.moveRow(at: IndexPath(row: oldIndex, section: 0), to: IndexPath(row: newIndex, section: 0))
    }

    func tunnelRemoved(at index: Int, tunnel: TunnelContainer) {
        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        centeredAddButton.isHidden = tunnelsManager?.numberOfTunnels() ?? 0 > 0
        if detailDisplayedTunnel == tunnel, let splitViewController = splitViewController {
            if splitViewController.isCollapsed != false {
                (splitViewController.viewControllers[0] as? UINavigationController)?.popToRootViewController(animated: false)
            } else {
                let detailVC = UIViewController()
                detailVC.view.backgroundColor = .systemBackground
                let detailNC = UINavigationController(rootViewController: detailVC)
                splitViewController.showDetailViewController(detailNC, sender: self)
            }
            detailDisplayedTunnel = nil
            if let presentedNavController = self.presentedViewController as? UINavigationController, presentedNavController.viewControllers.first is TunnelEditTableViewController {
                self.presentedViewController?.dismiss(animated: false, completion: nil)
            }
        }
    }
}
*/

extension UISplitViewController {
    func showDetailViewController(_ viewController: UIViewController, sender: Any?, animated: Bool) {
        if animated {
            showDetailViewController(viewController, sender: sender)
        } else {
            UIView.performWithoutAnimation {
                showDetailViewController(viewController, sender: sender)
            }
        }
    }
}

