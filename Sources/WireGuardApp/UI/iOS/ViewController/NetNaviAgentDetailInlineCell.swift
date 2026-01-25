//
// Copyright © 2025 Freecomm. All Rights Reserved.

import UIKit

// MARK: - Pro Tile View

final class NetNaviTileView: UIView {

    let leftBar = UIView()
    private let container = UIView()
    private let mainStack = UIStackView()
    private let headerStack = UIStackView()
    let bodyStack = UIStackView()

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separator = UIView()

    private var minHeightConstraint: NSLayoutConstraint!
    private let bodySpacer = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configureHeader(title: String,
                         subtitle: String? = nil,
                         barColor: UIColor) {

        leftBar.backgroundColor = barColor
        titleLabel.text = title

        if let subtitle {
            subtitleLabel.text = subtitle
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }
    }

    func clearBody() {
        bodyStack.arrangedSubviews.forEach {
            if $0 !== bodySpacer {
                bodyStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }
    }

    private func buildUI() {
        backgroundColor = .clear

        addSubview(leftBar)
        addSubview(container)

        leftBar.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false

        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 14
        container.layer.cornerCurve = .continuous

        container.layer.maskedCorners = [
            .layerMaxXMinYCorner,
            .layerMaxXMaxYCorner
        ]

        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.08
        container.layer.shadowRadius = 8
        container.layer.shadowOffset = CGSize(width: 0, height: 4)

        NSLayoutConstraint.activate([
            leftBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftBar.topAnchor.constraint(equalTo: container.topAnchor),
            leftBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            leftBar.widthAnchor.constraint(equalToConstant: 10),

            container.leadingAnchor.constraint(equalTo: leftBar.trailingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)

            // heightAnchor.constraint(greaterThanOrEqualToConstant: 80)
        ])

        minHeightConstraint = heightAnchor.constraint(greaterThanOrEqualToConstant: 110)
        minHeightConstraint.isActive = true

        mainStack.axis = .vertical
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            mainStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            mainStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        buildHeader()
        buildBody()
    }

    private func buildHeader() {
        headerStack.axis = .vertical
        headerStack.spacing = 4

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.font = .systemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(subtitleLabel)
        headerStack.addArrangedSubview(separator)

        mainStack.addArrangedSubview(headerStack)
    }

    private func buildBody() {
        bodyStack.axis = .vertical
        bodyStack.spacing = 8

        bodySpacer.translatesAutoresizingMaskIntoConstraints = false
        bodySpacer.heightAnchor.constraint(equalToConstant: 8).isActive = true

        bodyStack.addArrangedSubview(bodySpacer)
        mainStack.addArrangedSubview(bodyStack)
    }
}

// MARK: - Inline Detail Cell

final class NetNaviAgentDetailInlineCell: UITableViewCell {

    private let rootStack = UIStackView()

    private let clientTile = NetNaviTileView()
    private let cloudTile  = NetNaviTileView()
    private let liveTile   = NetNaviTileView()
    private let controlTile = NetNaviTileView()

    private weak var tunnel: TunnelContainer?
    private weak var manager: TunnelsManager?

    private var statusObs: NSKeyValueObservation?
    private var ondemandObs: NSKeyValueObservation?
    private var timer: Timer?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        stopTimer()
        statusObs = nil
        ondemandObs = nil
    }

    private func build() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .systemGroupedBackground

        rootStack.axis = .vertical
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)

        [clientTile, cloudTile, liveTile, controlTile].forEach {
            rootStack.addArrangedSubview($0)
        }

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - Bind

    func bind(tunnel: TunnelContainer, manager: TunnelsManager) {
        self.tunnel = tunnel
        self.manager = manager

        renderAll() // initial render

        statusObs = tunnel.observe(\.status, options: [.new]) { [weak self] _, _ in
            self?.renderStatus()
            self?.renderControls()
            self?.startOrStopTimer()
        }

        ondemandObs = tunnel.observe(\.isActivateOnDemandEnabled, options: [.new]) { [weak self] _, _ in
            self?.renderControls()
        }

        startOrStopTimer()
    }

    // MARK: - Render

    private func renderAll() {
        renderStatus()
        renderCloud()
        renderControls()
        renderRuntime(nil)
    }

    private func renderStatus() {
        guard let t = tunnel else { return }

        clientTile.configureHeader(
            title: t.name,
            subtitle: "Plus Service",
            barColor: statusColor(t.status)
        )

        clientTile.clearBody()

        let statusLabel = makeKV("Status", statusText(t.status))
        statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        clientTile.bodyStack.addArrangedSubview(statusLabel)

        if let cfg = t.tunnelConfiguration,
           let addr = cfg.interface.addresses.first?.stringRepresentation {
            clientTile.bodyStack.addArrangedSubview(makeKV("Address", addr))
        }
    }

    private func renderCloud() {
        guard let t = tunnel else { return }

        cloudTile.configureHeader(title: "NetNavi Cloud Service",
                                  barColor: .systemGreen)
        cloudTile.clearBody()

        if let cfg = t.tunnelConfiguration {
            if let host = cfg.peers.first?.endpoint?.host {
                cloudTile.bodyStack.addArrangedSubview(makeKV("GEO", host.debugDescription))
            } else {
                cloudTile.bodyStack.addArrangedSubview(makeKV("GEO", "-"))
            }
        }

    }

    private func renderRuntime(_ cfg: TunnelConfiguration? = nil) {
        guard let t = tunnel else { return }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var lastHandshake: Date?

        if let cfg = cfg {
            rx = cfg.peers.reduce(0) { $0 + ($1.rxBytes ?? 0) }
            tx = cfg.peers.reduce(0) { $0 + ($1.txBytes ?? 0) }
            lastHandshake = cfg.peers.compactMap({ $0.lastHandshakeTime }).max()
        }

        // Bar color logic: red if received < 1KB
        let barColor: UIColor = (rx < 1024 && lastHandshake == nil) ? .systemRed : .systemGreen

        liveTile.configureHeader(title: "NetNavi Live",
                                 subtitle: "Usage",
                                 barColor: barColor)
        liveTile.clearBody()

        if cfg != nil {
            // Active tunnel: show real data
            liveTile.bodyStack.addArrangedSubview(makeKV("Received", format(rx)))
            liveTile.bodyStack.addArrangedSubview(makeKV("Sent", format(tx)))

            if let t = lastHandshake {
                liveTile.bodyStack.addArrangedSubview(makeKV("Liveness Check", handshake(t)))
            }
        } else {
            // Inactive tunnel: show placeholders
            liveTile.bodyStack.addArrangedSubview(makeKV("Received", "0 B"))
            liveTile.bodyStack.addArrangedSubview(makeKV("Sent", "0 B"))
            liveTile.bodyStack.addArrangedSubview(makeKV("Liveness Check", "-"))
        }

        if t.status == .active {
            tunnel?.getRuntimeTunnelConfiguration { [weak self] cfg in
                DispatchQueue.main.async {
                    self?.renderRuntime(cfg)
                }
            }
        }
    }

    private func renderControls() {
        guard let t = tunnel else { return }

        controlTile.configureHeader(title: "Quick Controls",
                                    barColor: .systemIndigo)
        controlTile.clearBody()

        controlTile.bodyStack.addArrangedSubview(makeButton(
            t.status == .active ? "Disable" : "Enable",
            color: t.status == .active ? .systemRed : .systemGreen
        ) { [weak self] in
            guard let self else { return }
            t.status == .active
            ? self.manager?.startDeactivation(of: t)
            : self.manager?.startActivation(of: t)
        })

        controlTile.bodyStack.addArrangedSubview(makeButton("Reconnect", color: .systemOrange) { [weak self] in
            guard let self else { return }
            self.manager?.startDeactivation(of: t)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.manager?.startActivation(of: t)
            }
        })
    }

    // MARK: - Runtime

    private func startTimer() {
        stopTimer()
        reloadRuntime()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.reloadRuntime()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        // make sure the Live Status has the title
        // renderRuntime(nil)
    }

    /*
    private func reloadRuntime() {
        tunnel?.getRuntimeTunnelConfiguration { [weak self] cfg in
            DispatchQueue.main.async {
                self?.renderRuntime(cfg)
            }
        }
    }
     */
    private func reloadRuntime() {
        guard let t = tunnel, t.status == .active else {
            // inactive → only ensure placeholder once
            renderRuntime(nil)
            return
        }

        tunnel?.getRuntimeTunnelConfiguration { [weak self] cfg in
            DispatchQueue.main.async {
                self?.renderRuntime(cfg)
            }
        }
    }

    private func startOrStopTimer() {
        guard let t = tunnel else { return }

        stopTimer()

        renderRuntime(nil) // always reset live tile once

        if t.status == .active {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.reloadRuntime()
            }
            reloadRuntime()
        }
    }

    // MARK: - UI helpers

    private func makeKV(_ k: String, _ v: String) -> UILabel {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.numberOfLines = 0
        l.text = "\(k): \(v)"
        return l
    }

    private func makeButton(_ title: String, color: UIColor, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.backgroundColor = color.withAlphaComponent(0.12)
        b.setTitleColor(color, for: .normal)
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return b
    }

    private func statusText(_ s: TunnelStatus) -> String {
        switch s {
        case .inactive: return "Inactive"
        case .activating: return "Activating"
        case .active: return "Active"
        case .deactivating: return "Deactivating"
        case .reasserting: return "Reasserting"
        case .restarting: return "Restarting"
        case .waiting: return "Waiting"
        @unknown default: return "Unknown"
        }
    }

    private func statusColor(_ s: TunnelStatus) -> UIColor {
        switch s {
        case .active: return .systemGreen
        case .activating, .reasserting, .restarting: return .systemOrange
        case .deactivating: return .systemYellow
        default: return .systemGray
        }
    }

    private func format(_ v: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .binary)
    }

    private func handshake(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 60 ? "\(s)s ago" : s < 3600 ? "\(s/60)m ago" : "\(s/3600)h ago"
    }
}
