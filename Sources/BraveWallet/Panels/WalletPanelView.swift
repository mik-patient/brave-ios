// Copyright 2022 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import SwiftUI
import BraveCore
import DesignSystem
import Strings
import Data
import BraveShared

public protocol WalletSiteConnectionDelegate {
  /// A list of accounts connected to this webpage (addresses)
  var connectedAccounts: [String] { get }
  /// Update the connection status for a given account
  func updateConnectionStatusForAccountAddress(_ address: String)
}

public struct WalletPanelContainerView: View {
  var walletStore: WalletStore
  @ObservedObject var keyringStore: KeyringStore
  @ObservedObject var tabDappStore: TabDappStore
  var origin: URLOrigin
  var presentWalletWithContext: ((PresentingContext) -> Void)?
  var presentBuySendSwap: (() -> Void)?
  /// An invisible `UIView` background lives in SwiftUI for UIKit API to reference later
  var buySendSwapBackground: InvisibleUIView = .init()
  
  private enum VisibleScreen: Equatable {
    case loading
    case panel
    case onboarding
    case unlock
  }

  private var visibleScreen: VisibleScreen {
    let keyring = keyringStore.defaultKeyring
    // check if we are still fetching the `defaultKeyring`
    if keyringStore.defaultKeyring.id.isEmpty {
      return .loading
    }
    // keyring fetched, check if user has created a wallet
    if !keyring.isKeyringCreated || keyringStore.isOnboardingVisible {
      return .onboarding
    }
    // keyring fetched & wallet setup, but selected account not fetched
    if keyringStore.selectedAccount.address.isEmpty {
      return .loading
    }
    // keyring fetched & wallet setup, wallet is locked
    if keyring.isLocked || keyringStore.isRestoreFromUnlockBiometricsPromptVisible { // wallet is locked
      return .unlock
    }
    return .panel
  }
  
  private var lockedView: some View {
    VStack(spacing: 36) {
      Image("graphic-lock", bundle: .module)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxWidth: 150)
      Button {
        presentWalletWithContext?(.panelUnlockOrSetup)
      } label: {
        HStack(spacing: 4) {
          Image(braveSystemName: "brave.unlock")
          Text(Strings.Wallet.walletPanelUnlockWallet)
        }
      }
      .buttonStyle(BraveFilledButtonStyle(size: .normal))
    }
    .padding()
    .padding()
    .frame(maxWidth: .infinity)
    .background(Color(.braveBackground).ignoresSafeArea())
  }
  
  private var setupView: some View {
    ScrollView(.vertical) {
      VStack(spacing: 36) {
        VStack(spacing: 4) {
          Text(Strings.Wallet.braveWallet)
            .foregroundColor(Color(.bravePrimary))
            .font(.headline)
          Text(Strings.Wallet.walletPanelSetupWalletDescription)
            .foregroundColor(Color(.secondaryBraveLabel))
            .font(.subheadline)
        }
        .multilineTextAlignment(.center)
        Button {
          presentWalletWithContext?(.panelUnlockOrSetup)
        } label: {
          Text(Strings.Wallet.learnMoreButton)
        }
        .buttonStyle(BraveFilledButtonStyle(size: .normal))
      }
      .padding()
      .padding()
    }
    .frame(maxWidth: .infinity)
    .background(Color(.braveBackground).ignoresSafeArea())
  }
  
  public var body: some View {
    ZStack {
      switch visibleScreen {
      case .loading:
        lockedView
          .hidden() // used for sizing to prevent #5378
          .accessibilityHidden(true)
        Color.white
          .overlay(ProgressView())
      case .panel:
        if let cryptoStore = walletStore.cryptoStore {
          WalletPanelView(
            keyringStore: keyringStore,
            cryptoStore: cryptoStore,
            networkStore: cryptoStore.networkStore,
            accountActivityStore: cryptoStore.accountActivityStore(for: keyringStore.selectedAccount),
            tabDappStore: tabDappStore,
            origin: origin,
            presentWalletWithContext: { context in
              self.presentWalletWithContext?(context)
            },
            presentBuySendSwap: {
              self.presentBuySendSwap?()
            },
            buySendSwapBackground: buySendSwapBackground
          )
          .transition(.asymmetric(insertion: .identity, removal: .opacity))
        }
      case .unlock:
        lockedView
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(1)
      case .onboarding:
        setupView
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .zIndex(2)  // Needed or the dismiss animation messes up
      }
    }
    .frame(idealWidth: 320, maxWidth: .infinity)
    .onChange(of: keyringStore.defaultKeyring) { newValue in
      if visibleScreen != .panel, !keyringStore.lockedManually {
        presentWalletWithContext?(.panelUnlockOrSetup)
      }
    }
  }
}

struct WalletPanelView: View {
  @ObservedObject var keyringStore: KeyringStore
  @ObservedObject var cryptoStore: CryptoStore
  @ObservedObject var networkStore: NetworkStore
  @ObservedObject var accountActivityStore: AccountActivityStore
  @ObservedObject var allowSolProviderAccess: Preferences.Option<Bool> = Preferences.Wallet.allowSolProviderAccess
  @ObservedObject var tabDappStore: TabDappStore
  var origin: URLOrigin
  var presentWalletWithContext: (PresentingContext) -> Void
  var presentBuySendSwap: () -> Void
  var buySendSwapBackground: InvisibleUIView
  
  @Environment(\.pixelLength) private var pixelLength
  @Environment(\.sizeCategory) private var sizeCategory
  @ScaledMetric private var blockieSize = 54
  
  private let currencyFormatter: NumberFormatter = .usdCurrencyFormatter
  
  init(
    keyringStore: KeyringStore,
    cryptoStore: CryptoStore,
    networkStore: NetworkStore,
    accountActivityStore: AccountActivityStore,
    tabDappStore: TabDappStore,
    origin: URLOrigin,
    presentWalletWithContext: @escaping (PresentingContext) -> Void,
    presentBuySendSwap: @escaping () -> Void,
    buySendSwapBackground: InvisibleUIView
  ) {
    self.keyringStore = keyringStore
    self.cryptoStore = cryptoStore
    self.networkStore = networkStore
    self.accountActivityStore = accountActivityStore
    self.tabDappStore = tabDappStore
    self.origin = origin
    self.presentWalletWithContext = presentWalletWithContext
    self.presentBuySendSwap = presentBuySendSwap
    self.buySendSwapBackground = buySendSwapBackground
    
    currencyFormatter.currencyCode = accountActivityStore.currencyCode
  }
  
  @State private var ethPermittedAccounts: [String] = []
  @State private var solConnectedAddresses: Set<String> = .init()
  @State private var isConnectHidden: Bool = false
  
  enum ConnectionStatus {
    case connected
    case disconnected
    case blocked
    
    func title(_ coin: BraveWallet.CoinType) -> String {
      if WalletDebugFlags.isSolanaDappsEnabled {
        switch self {
        case .connected:
          return Strings.Wallet.walletPanelConnected
        case .disconnected:
          if coin == .eth {
            return Strings.Wallet.walletPanelConnect
          } else {
            return Strings.Wallet.walletPanelDisconnected
          }
        case .blocked:
          return Strings.Wallet.walletPanelBlocked
        }
      } else {
        if self == .connected {
          return Strings.Wallet.walletPanelConnected
        }
        return Strings.Wallet.walletPanelConnect
      }
    }
  }
  
  private var accountStatus: ConnectionStatus {
    let selectedAccount = keyringStore.selectedAccount
    if WalletDebugFlags.isSolanaDappsEnabled {
      switch selectedAccount.coin {
      case .eth:
        return ethPermittedAccounts.contains(selectedAccount.address) ? .connected : .disconnected
      case .sol:
        if !allowSolProviderAccess.value {
          return .blocked
        } else {
          return solConnectedAddresses.contains(selectedAccount.address) ? .connected : .disconnected
        }
      case .fil:
        return .blocked
      @unknown default:
        return .blocked
      }
    } else {
      return ethPermittedAccounts.contains(selectedAccount.address) ? .connected : .disconnected
    }
  }
  
  @ViewBuilder private var connectButton: some View {
    Button {
      if accountStatus == .blocked {
        presentWalletWithContext(.settings)
      } else {
        presentWalletWithContext(.editSiteConnection(origin, handler: { accounts in
          if keyringStore.selectedAccount.coin == .eth {
            ethPermittedAccounts = accounts
          }
        }))
      }
    } label: {
      HStack {
        if WalletDebugFlags.isSolanaDappsEnabled {
          if keyringStore.selectedAccount.coin == .sol {
            Circle()
              .strokeBorder(.white, lineWidth: 1)
              .background(
                Circle()
                  .foregroundColor(accountStatus == .connected ? .green : .red)
              )
              .frame(width: 12, height: 12)
            Text(accountStatus.title(keyringStore.selectedAccount.coin))
              .fontWeight(.bold)
              .lineLimit(1)
          } else {
            if accountStatus == .connected {
              Image(systemName: "checkmark")
            }
            Text(accountStatus.title(keyringStore.selectedAccount.coin))
              .fontWeight(.bold)
              .lineLimit(1)
          }
        } else {
          if accountStatus == .connected {
            Image(systemName: "checkmark")
          }
          Text(accountStatus.title(keyringStore.selectedAccount.coin))
            .fontWeight(.bold)
            .lineLimit(1)
        }
      }
      .foregroundColor(.white)
      .font(.caption.weight(.semibold))
      .padding(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
      .background(
        Color.white.opacity(0.5)
          .clipShape(Capsule().inset(by: 0.5).stroke())
      )
      .clipShape(Capsule())
      .contentShape(Capsule())
    }
  }
  
  private var networkPickerButton: some View {
    NetworkPicker(
      style: .init(textColor: .white, borderColor: .white),
      keyringStore: keyringStore,
      networkStore: networkStore
    )
  }
  
  private var pendingRequestsButton: some View {
    Button(action: { presentWalletWithContext(.pendingRequests) }) {
      Image(braveSystemName: "brave.bell.badge")
        .foregroundColor(.white)
        .frame(minWidth: 30, minHeight: 44)
        .contentShape(Rectangle())
    }
  }
  
  private var fullscreenButton: some View {
    Button {
      presentWalletWithContext(.default)
    } label: {
      Image(systemName: "arrow.up.left.and.arrow.down.right")
        .rotationEffect(.init(degrees: 90))
        .frame(minWidth: 30, minHeight: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(Strings.Wallet.walletFullScreenAccessibilityTitle)
  }
  
  private var menuButton: some View {
    Menu {
      Button(action: { keyringStore.lock() }) {
        Label(Strings.Wallet.lock, braveSystemImage: "brave.lock")
      }
      Divider()
      Button(action: { presentWalletWithContext(.settings) }) {
        Label(Strings.Wallet.settings, braveSystemImage: "brave.gear")
      }
    } label: {
      Image(systemName: "ellipsis")
        .frame(minWidth: 30, minHeight: 44)
        .contentShape(Rectangle())
    }
    .accessibilityLabel(Strings.Wallet.otherWalletActionsAccessibilityTitle)
  }
  
  /// A boolean value indicates to hide or unhide `Connect` button
  private func isConnectButtonHidden() -> Bool {
    guard WalletDebugFlags.isSolanaDappsEnabled else { return false }
    let account = keyringStore.selectedAccount
    if account.coin == .sol {
      for domain in Domain.allDomainsWithWalletPermissions(for: .sol) {
        if let accounts = domain.wallet_solanaPermittedAcccounts, !accounts.isEmpty {
          return false
        }
      }
      return true
    } else {
      return false
    }
  }
  
  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 0) {
        if sizeCategory.isAccessibilityCategory {
          VStack {
            Text(Strings.Wallet.braveWallet)
              .font(.headline)
              .background(
                Color.clear
              )
            HStack {
              fullscreenButton
              Spacer()
              if cryptoStore.pendingRequest != nil {
                pendingRequestsButton
                Spacer()
              }
              menuButton
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
          .overlay(
            Color.white.opacity(0.3) // Divider
              .frame(height: pixelLength),
            alignment: .bottom
          )
        } else {
          HStack {
            fullscreenButton
            if cryptoStore.pendingRequest != nil {
              // fake bell icon for layout
              pendingRequestsButton
              .hidden()
            }
            Spacer()
            Text(Strings.Wallet.braveWallet)
              .font(.headline)
              .background(
                Color.clear
              )
            Spacer()
            if cryptoStore.pendingRequest != nil {
              pendingRequestsButton
            }
            menuButton
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 4)
          .overlay(
            Color.white.opacity(0.3) // Divider
              .frame(height: pixelLength),
            alignment: .bottom
          )
        }
        VStack {
          if sizeCategory.isAccessibilityCategory {
            VStack {
              if !isConnectHidden {
                connectButton
              }
              networkPickerButton
            }
          } else {
            HStack {
              if !isConnectHidden {
                connectButton
              }
              Spacer()
              networkPickerButton
            }
          }
          VStack(spacing: 12) {
            Button {
              presentWalletWithContext(.accountSelection)
            } label: {
              Blockie(address: keyringStore.selectedAccount.address)
                .frame(width: blockieSize, height: blockieSize)
                .overlay(
                  Circle().strokeBorder(lineWidth: 2, antialiased: true)
                )
                .overlay(
                  Image(systemName: "chevron.down.circle.fill")
                    .font(.footnote)
                    .background(Color(.braveLabel).clipShape(Circle())),
                  alignment: .bottomLeading
                )
            }
            VStack(spacing: 4) {
              Text(keyringStore.selectedAccount.name)
                .font(.headline)
              AddressView(address: keyringStore.selectedAccount.address) {
                Text(keyringStore.selectedAccount.address.truncatedAddress)
                  .font(.callout)
                  .multilineTextAlignment(.center)
              }
            }
          }
          VStack(spacing: 4) {
            let nativeAsset = accountActivityStore.assets.first(where: { $0.token.symbol == networkStore.selectedChain.symbol })
            Text(String(format: "%.04f %@", nativeAsset?.decimalBalance ?? 0.0, networkStore.selectedChain.symbol))
              .font(.title2.weight(.bold))
            Text(currencyFormatter.string(from: NSNumber(value: (Double(nativeAsset?.price ?? "") ?? 0) * (nativeAsset?.decimalBalance ?? 0.0))) ?? "")
              .font(.callout)
          }
          .padding(.vertical)
          HStack(spacing: 0) {
            Button {
              presentBuySendSwap()
            } label: {
              Image(braveSystemName: "brave.arrow.left.arrow.right")
                .imageScale(.large)
                .padding(.horizontal, 44)
                .padding(.vertical, 8)
            }
            .background(buySendSwapBackground)
            Color.white.opacity(0.6)
              .frame(width: pixelLength)
            Button {
              presentWalletWithContext(.transactionHistory)
            } label: {
              Image(braveSystemName: "brave.history")
                .imageScale(.large)
                .padding(.horizontal, 44)
                .padding(.vertical, 8)
            }
          }
          .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.6), style: .init(lineWidth: pixelLength)))
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 24, trailing: 12))
      }
    }
    .foregroundColor(.white)
    .background(
      BlockieMaterial(address: keyringStore.selectedAccount.id)
      .ignoresSafeArea()
    )
    .onChange(of: cryptoStore.pendingRequest) { newValue in
      if newValue != nil {
        presentWalletWithContext(.pendingRequests)
      }
    }
    .onChange(of: tabDappStore.solConnectedAddresses) { newValue in
      solConnectedAddresses = newValue
    }
    .onChange(of: keyringStore.selectedAccount) { _ in
      isConnectHidden = isConnectButtonHidden()
    }
    .onAppear {
      let permissionRequestManager = WalletProviderPermissionRequestsManager.shared
      if let request = permissionRequestManager.pendingRequests(for: origin, coinType: .eth).first {
        presentWalletWithContext(.requestEthererumPermissions(request, onPermittedAccountsUpdated: { accounts in
          if request.coinType == .eth {
            ethPermittedAccounts = accounts
          } else if request.coinType == .sol {
            isConnectHidden = false
          }
        }))
      } else {
        cryptoStore.prepare()
      }
      if let url = origin.url, let accounts = Domain.walletPermissions(forUrl: url, coin: .eth) {
        ethPermittedAccounts = accounts
      }
      
      solConnectedAddresses = tabDappStore.solConnectedAddresses
      
      isConnectHidden = isConnectButtonHidden()
      
      accountActivityStore.update()
    }
  }
}

struct InvisibleUIView: UIViewRepresentable {
  let uiView = UIView()
  func makeUIView(context: Context) -> UIView {
    uiView.backgroundColor = .clear
    return uiView
  }
  func updateUIView(_ uiView: UIView, context: Context) {
  }
}

#if DEBUG
struct WalletPanelView_Previews: PreviewProvider {
  static var previews: some View {
    Group {
      WalletPanelView(
        keyringStore: .previewStoreWithWalletCreated,
        cryptoStore: .previewStore,
        networkStore: .previewStore,
        accountActivityStore: .previewStore,
        tabDappStore: .previewStore,
        origin: .init(url: URL(string: "https://app.uniswap.org")!),
        presentWalletWithContext: { _ in },
        presentBuySendSwap: {},
        buySendSwapBackground: InvisibleUIView()
      )
      WalletPanelView(
        keyringStore: .previewStore,
        cryptoStore: .previewStore,
        networkStore: .previewStore,
        accountActivityStore: .previewStore,
        tabDappStore: .previewStore,
        origin: .init(url: URL(string: "https://app.uniswap.org")!),
        presentWalletWithContext: { _ in },
        presentBuySendSwap: {},
        buySendSwapBackground: InvisibleUIView()
      )
      WalletPanelView(
        keyringStore: {
          let store = KeyringStore.previewStoreWithWalletCreated
          store.lock()
          return store
        }(),
        cryptoStore: .previewStore,
        networkStore: .previewStore,
        accountActivityStore: .previewStore,
        tabDappStore: .previewStore,
        origin: .init(url: URL(string: "https://app.uniswap.org")!),
        presentWalletWithContext: { _ in },
        presentBuySendSwap: {},
        buySendSwapBackground: InvisibleUIView()
      )
    }
    .fixedSize(horizontal: false, vertical: true)
    .previewLayout(.sizeThatFits)
  }
}
#endif
