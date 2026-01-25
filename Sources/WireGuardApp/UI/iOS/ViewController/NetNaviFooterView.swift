//
//
import UIKit

final class NetNaviFooterView: UIView {

    // MARK: - Constants

    private let baseHeight: CGFloat = 85
    private let extraBottomInset: CGFloat = 24

    // MARK: - UI

    private let container = UIView()
    private let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let stackView = UIStackView()

    // MARK: - Init

    init(primaryAction: @escaping () -> Void,
         portalAction: @escaping () -> Void,
         settingsAction: @escaping () -> Void) {

        super.init(frame: .zero)
        buildUI(primaryAction: primaryAction,
                portalAction: portalAction,
                settingsAction: settingsAction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public

    func attach(to scrollView: UIScrollView) {
        layoutIfNeeded()
        let totalHeight = baseHeight + safeAreaInsets.bottom + extraBottomInset

        var inset = scrollView.contentInset
        inset.bottom = max(inset.bottom, totalHeight)
        scrollView.contentInset = inset
        scrollView.scrollIndicatorInsets = inset
    }

    // MARK: - Build

    private func buildUI(primaryAction: @escaping () -> Void,
                         portalAction: @escaping () -> Void,
                         settingsAction: @escaping () -> Void) {

        setupContainer()
        setupBackground()
        setupButtons(primaryAction: primaryAction,
                     portalAction: portalAction,
                     settingsAction: settingsAction)
        layoutUI()
    }

    private func setupContainer() {
        addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupBackground() {
        backgroundView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        backgroundView.layer.cornerCurve = .continuous
        backgroundView.clipsToBounds = true

        backgroundView.layer.shadowColor = UIColor.black.cgColor
        backgroundView.layer.shadowOpacity = 0.12
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: -3)
        backgroundView.layer.shadowRadius = 12

        container.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: container.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func setupButtons(primaryAction: @escaping () -> Void,
                              portalAction: @escaping () -> Void,
                              settingsAction: @escaping () -> Void) {

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalSpacing
        stackView.spacing = 36

        let gptButton = makeNetNaviFooterButton(
            title: "NetNaviGPT",
            systemImage: "bubble.left.and.bubble.right",
            highlighted: true,
            action: primaryAction
        )

        let portalButton = makeNetNaviFooterButton(
            title: "Me",
            systemImage: "person",
            highlighted: false,
            action: portalAction
        )

        let settingsButton = makeNetNaviFooterButton(
            title: tr("tunnelsListSettingsButtonTitle"),
            systemImage: "headphones",
            highlighted: false,
            action: settingsAction
        )

        stackView.addArrangedSubview(gptButton)
        stackView.addArrangedSubview(portalButton)
        stackView.addArrangedSubview(settingsButton)

        backgroundView.contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func layoutUI() {
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: baseHeight + safeAreaInsets.bottom),

            stackView.centerXAnchor.constraint(equalTo: backgroundView.centerXAnchor),
            stackView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14)
        ])
    }

    final class FooterButton: UIButton {

        private let onTap: () -> Void

        init(action: @escaping () -> Void) {
            self.onTap = action
            super.init(frame: .zero)
            addTarget(self, action: #selector(tapped), for: .touchUpInside)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func tapped() {
            onTap()
        }

        func applyAppStoreFeedbackStyle(highlightedColor: UIColor) {
            configurationUpdateHandler = { button in
                guard var config = button.configuration else { return }
                switch button.state {
                case .highlighted:
                    config.baseForegroundColor = highlightedColor.withAlphaComponent(0.6)
                    button.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
                default:
                    config.baseForegroundColor = highlightedColor
                    button.transform = .identity
                }
                button.configuration = config
            }
        }
    }

    private func makeNetNaviFooterButton(
        title: String,
        systemImage: String,
        highlighted: Bool,
        action: @escaping () -> Void
    ) -> UIButton {

        let button = FooterButton(action: action)

        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()

            let color: UIColor = highlighted ? .systemTeal : .secondaryLabel

            config.image = UIImage(systemName: systemImage)
            config.imagePlacement = .top
            config.imagePadding = 6
            config.preferredSymbolConfigurationForImage =
                UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)

            var attr = AttributeContainer()
            let baseFont = UIFont.systemFont(ofSize: 10, weight: highlighted ? .semibold : .regular)
            attr.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            attr.foregroundColor = color

            config.attributedTitle = AttributedString(title, attributes: attr)
            config.baseForegroundColor = color
            config.background.backgroundColor = .clear

            config.contentInsets = NSDirectionalEdgeInsets(
                top: 2,
                leading: 6,
                bottom: 2,
                trailing: 6
            )
            button.configuration = config
            button.applyAppStoreFeedbackStyle(highlightedColor: color)
        }

        return button
    }

}
