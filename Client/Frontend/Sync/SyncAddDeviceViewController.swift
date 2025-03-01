/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import BraveShared
import BraveCore
import Data
import BraveWallet
import BraveUI

enum DeviceType {
  case mobile
  case computer
}

class SyncAddDeviceViewController: SyncViewController {
  var doneHandler: (() -> Void)?

  private let barcodeSize: CGFloat = 200.0

  lazy var stackView: UIStackView = {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.distribution = .equalSpacing
    stack.spacing = 4
    return stack
  }()

  lazy var codewordsView: UILabel = {
    let label = UILabel()
    label.font = UIFont.systemFont(ofSize: 18.0, weight: UIFont.Weight.medium)
    label.lineBreakMode = NSLineBreakMode.byWordWrapping
    label.numberOfLines = 0
    return label
  }()

  lazy var copyPasteButton: UIButton = {
    let button = UIButton()
    button.setTitle(Strings.copyToClipboard, for: .normal)
    button.addTarget(self, action: #selector(SEL_copy), for: .touchUpInside)
    button.setTitleColor(UIColor.braveOrange, for: .normal)
    button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    button.isHidden = true
    return button
  }()
  var controlContainerView: UIView!
  var containerView: UIView!
  var qrCodeView: SyncQRCodeView?
  var modeControl: UISegmentedControl!
  var titleLabel: UILabel!
  var descriptionLabel: UILabel!
  var doneButton: RoundInterfaceButton!
  var enterWordsButton: RoundInterfaceButton!
  var pageTitle: String = Strings.sync
  var deviceType: DeviceType = .mobile
  var didCopy = false {
    didSet {
      if didCopy {
        copyPasteButton.setTitle(Strings.copiedToClipboard, for: .normal)
      } else {
        copyPasteButton.setTitle(Strings.copyToClipboard, for: .normal)
      }
    }
  }

  private let syncAPI: BraveSyncAPI

  init(title: String, type: DeviceType, syncAPI: BraveSyncAPI) {
    self.syncAPI = syncAPI
    super.init(nibName: nil, bundle: nil)

    pageTitle = title
    deviceType = type
  }

  @available(*, unavailable)
  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    title = deviceType == .computer ? Strings.syncAddComputerTitle : Strings.syncAddTabletOrPhoneTitle

    view.addSubview(stackView)
    stackView.snp.makeConstraints { make in
      make.top.equalTo(self.view.safeArea.top).inset(10)
      make.left.right.equalTo(self.view).inset(16)
      make.bottom.equalTo(self.view.safeArea.bottom).inset(24)
    }

    controlContainerView = UIView()
    controlContainerView.translatesAutoresizingMaskIntoConstraints = false

    containerView = UIView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    containerView.layer.cornerRadius = 8
    containerView.layer.cornerCurve = .continuous
    containerView.layer.masksToBounds = true

    qrCodeView = SyncQRCodeView(syncApi: syncAPI)
    containerView.addSubview(qrCodeView!)
    qrCodeView?.snp.makeConstraints { make in
      make.top.bottom.equalTo(0).inset(22)
      make.centerX.equalTo(self.containerView)
      make.size.equalTo(barcodeSize)
    }

    self.codewordsView.text = syncAPI.getTimeLimitedWords(fromWords: syncAPI.getSyncCode())
    self.setupVisuals()
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    
    if !syncAPI.isInSyncGroup {
      showInitializationError()
    }
  }

  private func showInitializationError() {
    present(SyncAlerts.initializationError, animated: true)
  }

  private func setupVisuals() {
    modeControl = UISegmentedControl(items: [Strings.QRCode, Strings.codeWords])
    modeControl.translatesAutoresizingMaskIntoConstraints = false
    modeControl.selectedSegmentIndex = 0
    modeControl.addTarget(self, action: #selector(SEL_changeMode), for: .valueChanged)
    modeControl.isHidden = deviceType == .computer
    modeControl.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

    modeControl.selectedSegmentTintColor = UIColor.braveOrange
    modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    stackView.addArrangedSubview(modeControl)

    let titleDescriptionStackView = UIStackView()
    titleDescriptionStackView.axis = .vertical
    titleDescriptionStackView.spacing = 2
    titleDescriptionStackView.alignment = .center

    titleLabel = UILabel()
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFont.Weight.semibold)
    titleLabel.textColor = .braveLabel
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
    titleDescriptionStackView.addArrangedSubview(titleLabel)

    descriptionLabel = UILabel()
    descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFont.Weight.regular)
    descriptionLabel.textColor = .braveLabel
    descriptionLabel.numberOfLines = 0
    descriptionLabel.lineBreakMode = .byTruncatingTail
    descriptionLabel.textAlignment = .center
    descriptionLabel.adjustsFontSizeToFitWidth = true
    descriptionLabel.minimumScaleFactor = 0.5
    descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    titleDescriptionStackView.addArrangedSubview(descriptionLabel)

    stackView.addArrangedSubview(titleDescriptionStackView)

    codewordsView.isHidden = true
    containerView.addSubview(codewordsView)
    stackView.addArrangedSubview(containerView)

    let doneEnterWordsStackView = UIStackView()
    doneEnterWordsStackView.axis = .vertical
    doneEnterWordsStackView.spacing = 4
    doneEnterWordsStackView.distribution = .fillEqually

    doneEnterWordsStackView.addArrangedSubview(copyPasteButton)

    doneButton = RoundInterfaceButton(type: .roundedRect)
    doneButton.translatesAutoresizingMaskIntoConstraints = false
    doneButton.setTitle(Strings.done, for: .normal)
    doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFont.Weight.bold)
    doneButton.setTitleColor(.white, for: .normal)
    doneButton.backgroundColor = .braveOrange
    doneButton.addTarget(self, action: #selector(SEL_done), for: .touchUpInside)

    doneEnterWordsStackView.addArrangedSubview(doneButton)

    enterWordsButton = RoundInterfaceButton(type: .roundedRect)
    enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
    enterWordsButton.setTitle(Strings.showCodeWords, for: .normal)
    enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFont.Weight.semibold)
    enterWordsButton.setTitleColor(.braveLabel, for: .normal)
    enterWordsButton.addTarget(self, action: #selector(SEL_showCodewords), for: .touchUpInside)

    doneEnterWordsStackView.setContentCompressionResistancePriority(.required, for: .vertical)

    stackView.addArrangedSubview(doneEnterWordsStackView)

    codewordsView.snp.makeConstraints {
      $0.edges.equalToSuperview()
    }

    doneButton.snp.makeConstraints { (make) in
      make.height.equalTo(40)
    }

    enterWordsButton.snp.makeConstraints { (make) in
      make.height.equalTo(20)
    }

    if deviceType == .computer {
      SEL_showCodewords()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateLabels()
  }

  private func updateLabels() {
    let isFirstIndex = modeControl.selectedSegmentIndex == 0

    titleLabel.text = isFirstIndex ? Strings.syncAddDeviceScan : Strings.syncAddDeviceWords

    if isFirstIndex {
      let description = Strings.syncAddDeviceScanDescription
      let attributedDescription = NSMutableAttributedString(string: description)

      if let lastSentenceRange = lastSentenceRange(text: description) {
        attributedDescription.addAttribute(.foregroundColor, value: UIColor.braveErrorLabel, range: lastSentenceRange)
      }

      descriptionLabel.attributedText = attributedDescription
    } else {
      // The button name should be the same as in codewords instructions.
      let buttonName = Strings.scanSyncCode
      let addDeviceWords = String(format: Strings.syncAddDeviceWordsDescription, buttonName)
      let description = NSMutableAttributedString(string: addDeviceWords)
      let fontSize = descriptionLabel.font.pointSize

      let boldRange = (addDeviceWords as NSString).range(of: buttonName)
      description.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: fontSize), range: boldRange)

      if let lastSentenceRange = lastSentenceRange(text: addDeviceWords) {
        description.addAttribute(.foregroundColor, value: UIColor.braveErrorLabel, range: lastSentenceRange)
      }

      descriptionLabel.attributedText = description
    }
  }

  private func lastSentenceRange(text: String) -> NSRange? {
    guard let lastSentence = text.split(separator: "\n").last else { return nil }
    return (text as NSString).range(of: String(lastSentence))
  }

  @objc func SEL_showCodewords() {
    modeControl.selectedSegmentIndex = 1
    enterWordsButton.isHidden = true
    SEL_changeMode()
  }

  @objc func SEL_copy() {
    if let words = self.codewordsView.text {
      UIPasteboard.general.setSecureString(words, expirationDate: Date().addingTimeInterval(30))
      didCopy = true
    }
  }

  @objc func SEL_changeMode() {
    let isFirstIndex = modeControl.selectedSegmentIndex == 0

    qrCodeView?.isHidden = !isFirstIndex
    codewordsView.isHidden = isFirstIndex
    copyPasteButton.isHidden = isFirstIndex

    updateLabels()
  }

  @objc func SEL_done() {
    doneHandler?()
  }
}
