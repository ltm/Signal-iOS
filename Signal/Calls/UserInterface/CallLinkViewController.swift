//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import Foundation
import SignalServiceKit
import SignalUI
import UIKit

final class CallLinkViewController: OWSTableViewController2 {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }
    override var navbarBackgroundColorOverride: UIColor? { tableBackgroundColor }

    private var db: any DB { DependenciesBridge.shared.db }
    private var callLinkStore: any CallLinkRecordStore { DependenciesBridge.shared.callLinkStore }

    private let callLink: CallLink

    /// Set if we're the admin for this call link.
    private let adminPasskey: Data?
    private let callLinkAdminManager: CallLinkAdminManager?

    /// The ROWID of the corresponding ``CallLinkRecord``. If `nil`, `rootKey`
    /// refers to a just-created call link that hasn't been persisted (it'll be
    /// persisted once it's shared).
    private var callLinkRowId: Int64?

    /// The latest known state for the call link. This usually matches what's on
    /// disk, but it might not be saved to disk yet for just-created call links.
    private var callLinkState: CallLinkState?

    /// Set if we're viewing the details for a call link that we've used.
    private let callRecords: [CallRecord]

    static func forExisting(callLinkRecord: CallLinkRecord, callRecords: [CallRecord]) -> CallLinkViewController {
        return CallLinkViewController(
            title: callRecords.isEmpty ? CallStrings.callLink : CallStrings.callDetails,
            callLink: CallLink(rootKey: callLinkRecord.rootKey),
            adminInfo: callLinkRecord.adminPasskey.map {
                return ($0, CallLinkAdminManager(
                    rootKey: callLinkRecord.rootKey,
                    adminPasskey: $0,
                    callLinkState: callLinkRecord.state
                ))
            },
            callLinkRowId: callLinkRecord.id,
            callLinkState: callLinkRecord.state,
            callRecords: callRecords
        )
    }

    static func forJustCreated(callLink: CallLink, adminPasskey: Data, callLinkState: CallLinkState) -> CallLinkViewController {
        let adminManager = CallLinkAdminManager(
            rootKey: callLink.rootKey,
            adminPasskey: adminPasskey,
            callLinkState: callLinkState
        )
        let result = CallLinkViewController(
            title: CallStrings.createCallLinkTitle,
            callLink: callLink,
            adminInfo: (adminPasskey, adminManager),
            callLinkRowId: nil,
            callLinkState: callLinkState,
            callRecords: []
        )
        // We need to learn about updates before `persistIfNeeded` is invoked.
        adminManager.didUpdateCallLinkState = { [weak result] callLinkState in
            result?.callLinkState = callLinkState
            result?.updateContents(shouldReload: true)
        }
        return result
    }

    private init(
        title: String,
        callLink: CallLink,
        adminInfo: (adminPasskey: Data, adminManager: CallLinkAdminManager)?,
        callLinkRowId: Int64?,
        callLinkState: CallLinkState?,
        callRecords: [CallRecord]
    ) {
        self.callLink = callLink
        self.adminPasskey = adminInfo?.adminPasskey
        self.callLinkAdminManager = adminInfo?.adminManager
        self.callLinkRowId = callLinkRowId
        self.callLinkState = callLinkState
        self.callRecords = callRecords

        super.init()
        self.title = title

        self.databaseStorage.appendDatabaseChangeDelegate(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateContents(shouldReload: false)
    }

    private func updateContents(shouldReload: Bool) {
        self.setContents(buildTableContents(), shouldReload: shouldReload)
    }

    private func callLinkCardCell() -> UITableViewCell {
        let cell = OWSTableItem.newCell()

        let view = CallLinkCardView(
            callLink: self.callLink,
            callName: self.callLinkState.localizedName,
            joinAction: { [unowned self] in self.joinCall() }
        )
        cell.contentView.addSubview(view)
        view.autoPinLeadingToSuperviewMargin()
        view.autoPinTrailingToSuperviewMargin()
        view.autoPinEdge(.top, to: .top, of: cell.contentView, withOffset: Constants.vMarginCallLinkCard)
        view.autoPinEdge(.bottom, to: .bottom, of: cell.contentView, withOffset: -Constants.vMarginCallLinkCard)

        cell.selectionStyle = .none
        return cell
    }

    private enum Constants {
        static let vMarginCallLinkCard: CGFloat = 12
    }

    private func buildTableContents() -> OWSTableContents {
        let callLinkCardItem = OWSTableItem(
            customCellBlock: { [weak self] in
                guard let self = self else { return UITableViewCell() }
                return self.callLinkCardCell()
            }
        )

        var settingSection: OWSTableSection?
        if let callLinkAdminManager {
            var settingItems = [OWSTableItem]()
            settingItems.append(.item(
                name: callLinkAdminManager.editCallNameButtonTitle,
                accessoryType: .disclosureIndicator,
                actionBlock: { [unowned self] in
                    let editNameViewController = EditCallLinkNameViewController(
                        oldCallName: self.callLinkState?.name ?? "",
                        setNewCallName: callLinkAdminManager.updateName(_:)
                    )
                    self.presentFormSheet(
                        OWSNavigationController(rootViewController: editNameViewController),
                        animated: true
                    )
                }
            ))
            settingItems.append(.switch(
                withText: CallStrings.approveAllMembers,
                isOn: { [unowned self] in
                    return (
                        self.callLinkState?.requiresAdminApproval
                        ?? CallLinkState.Constants.defaultRequiresAdminApproval
                    )
                },
                isEnabled: { [unowned self] in self.callLinkState != nil },
                actionBlock: { [unowned self] sender in
                    callLinkAdminManager.toggleApproveAllMembersWithActivityIndicator(sender, from: self)
                }
            ))
            settingSection = OWSTableSection(items: settingItems)
        }

        let sharingSection = OWSTableSection(items: [
            .item(
                icon: .buttonForward,
                name: CallStrings.shareLinkViaSignal,
                actionBlock: { [unowned self] in self.shareCallLinkViaSignal() }
            ),
            .item(
                icon: .buttonCopy,
                name: CallStrings.copyLinkToClipboard,
                actionBlock: { [unowned self] in self.copyCallLink() }
            ),
            OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.buildCell(
                        icon: .buttonShare,
                        itemName: CallStrings.shareLinkViaSystem
                    )
                    self.systemShareTableViewCell = cell
                    return cell
                },
                actionBlock: { [unowned self] in self.shareCallLinkViaSystem() }
            )
        ])
        sharingSection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + OWSTableItem.iconSize + OWSTableItem.iconSpacing

        return OWSTableContents(
            sections: [
                ConversationSettingsViewController.createCallHistorySection(callRecords: callRecords),
                OWSTableSection(items: [callLinkCardItem]),
                settingSection,
                sharingSection,
            ].compacted()
        )
    }

    private var systemShareTableViewCell: UITableViewCell?

    // MARK: - Actions

    /// Adds the Call Link to the Calls Tab.
    ///
    /// This should be called after the user makes an "escaping" change to the
    /// Call Link (eg sharing it or copying it) or when they explicitly tap
    /// "Done" to confirm it.
    func persistIfNeeded() {
        guard callLinkRowId == nil else {
            return
        }
        guard FeatureFlags.callLinkRecordTable else {
            return
        }
        callLinkRowId = createCallLinkRecord()
        callLinkAdminManager?.didUpdateCallLinkState = nil
    }

    private func createCallLinkRecord() -> Int64 {
        let rowId = databaseStorage.write { tx in
            var callLinkRecord: CallLinkRecord
            do {
                callLinkRecord = try callLinkStore.fetchOrInsert(rootKey: callLink.rootKey, tx: tx.asV2Write)
                callLinkRecord.adminPasskey = adminPasskey!
                callLinkRecord.updateState(callLinkState!)
                try callLinkStore.update(callLinkRecord, tx: tx.asV2Write)
            } catch {
                owsFail("Couldn't create CallLinkRecord: \(error)")
            }

            callLinkAdminManager?.sendCallLinkUpdateMessage(tx: tx)

            return callLinkRecord.id
        }
        storageServiceManager.recordPendingUpdates(callLinkRootKeys: [callLink.rootKey])
        return rowId
    }

    private func joinCall() {
        persistIfNeeded()
        GroupCallViewController.presentLobby(
            for: callLink,
            callLinkStateRetrievalStrategy: {
                // If the local user is the admin, then we expect to be aware of the latest
                // state. (This is true even on linked devices because we send
                // CallLinkUpdate messages.) In this case, don't issue a redundant fetch.
                if adminPasskey != nil, let callLinkState {
                    return .reuse(callLinkState)
                }
                // In all other cases, the admin may have changed the details, so we should
                // check when joining the call.
                return .fetch
            }()
        )
    }

    private func copyCallLink() {
        self.persistIfNeeded()
        UIPasteboard.general.url = self.callLink.url()
        self.presentToast(text: OWSLocalizedString(
            "COPIED_TO_CLIPBOARD",
            comment: "Indicator that a value has been copied to the clipboard."
        ))
    }

    private func shareCallLinkViaSystem() {
        self.persistIfNeeded()
        let shareViewController = UIActivityViewController(
            activityItems: [self.callLink.url()],
            applicationActivities: nil
        )
        shareViewController.popoverPresentationController?.sourceView = self.systemShareTableViewCell
        self.present(shareViewController, animated: true)
    }

    private var sendMessageFlow: SendMessageFlow?

    func shareCallLinkViaSignal() {
        let messageBody = MessageBody(text: callLink.url().absoluteString, ranges: .empty)
        let unapprovedContent = SendMessageUnapprovedContent.text(messageBody: messageBody)
        let sendMessageFlow = SendMessageFlow(
            flowType: .`default`,
            unapprovedContent: unapprovedContent,
            useConversationComposeForSingleRecipient: true,
            presentationStyle: .presentFrom(self),
            delegate: self
        )
        // Retain the flow until it is complete.
        self.sendMessageFlow = sendMessageFlow
    }
}

extension CallLinkViewController: DatabaseChangeDelegate {
    private func loadStateAndReloadViewIfNeeded(callLinkRowId: Int64) {
        let didChangeVisibleProperty: Bool
        do {
            let oldState = self.callLinkState
            let newState = try self.db.read { tx in try callLinkStore.fetch(rowId: callLinkRowId, tx: tx)?.state }
            didChangeVisibleProperty = (
                (oldState == nil) != (newState == nil)
                || (oldState?.name != newState?.name)
                || (oldState?.requiresAdminApproval != newState?.requiresAdminApproval)
            )
            self.callLinkState = newState
        } catch {
            owsFailDebug("Couldn't fetch CallLink: \(error)")
            return
        }
        if didChangeVisibleProperty, self.isViewLoaded {
            updateContents(shouldReload: true)
        }
    }

    func databaseChangesDidUpdate(databaseChanges: any DatabaseChanges) {
        guard let callLinkRowId else {
            return
        }
        guard databaseChanges.tableRowIds[CallLinkRecord.databaseTableName]?.contains(callLinkRowId) == true else {
            return
        }
        loadStateAndReloadViewIfNeeded(callLinkRowId: callLinkRowId)
    }

    func databaseChangesDidUpdateExternally() {
        guard let callLinkRowId else {
            return
        }
        loadStateAndReloadViewIfNeeded(callLinkRowId: callLinkRowId)
    }

    func databaseChangesDidReset() {
    }
}

extension CallLinkViewController: SendMessageDelegate {
    func sendMessageFlowDidComplete(threads: [TSThread]) {
        AssertIsOnMainThread()

        sendMessageFlow?.dismissNavigationController(animated: true)

        sendMessageFlow = nil
    }

    func sendMessageFlowDidCancel() {
        AssertIsOnMainThread()

        sendMessageFlow?.dismissNavigationController(animated: true)

        sendMessageFlow = nil
    }
}

// MARK: - CallLinkCardView

private class CallLinkCardView: UIView {
    private lazy var iconView: UIImageView = {
        let image = CommonCallLinksUI.callLinkIcon()
        let imageView = UIImageView(image: image)
        imageView.autoSetDimensions(to: CGSize(
            width: Constants.circleViewDimension,
            height: Constants.circleViewDimension
        ))
        return imageView
    }()

    private lazy var textStack: UIStackView = {
        let stackView = UIStackView()

        let nameLabel = UILabel()
        nameLabel.text = callName
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.numberOfLines = 0
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.font = .dynamicTypeHeadline

        let linkLabel = UILabel()
        linkLabel.text = callLink.url().absoluteString
        linkLabel.lineBreakMode = .byTruncatingTail
        linkLabel.numberOfLines = 2

        linkLabel.textColor = Theme.snippetColor
        linkLabel.font = .dynamicTypeBody2

        stackView.addArrangedSubviews([nameLabel, linkLabel])
        stackView.axis = .vertical
        stackView.spacing = Constants.textStackSpacing
        stackView.alignment = .leading

        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private let joinButton: UIButton

    private class JoinButton: UIButton {
        init(joinAction: @escaping () -> Void) {
            super.init(frame: .zero)

            let view = UIView()
            view.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray05
            view.isUserInteractionEnabled = false
            view.layer.cornerRadius = bounds.size.height / 2

            let label = UILabel()
            label.setCompressionResistanceHigh()
            label.text = CallStrings.joinCallPillButtonTitle
            label.font = UIFont.dynamicTypeSubheadlineClamped.semibold()
            label.textColor = Theme.accentBlueColor
            view.isUserInteractionEnabled = false

            self.clipsToBounds = true
            self.addAction(UIAction(handler: { _ in joinAction() }), for: .touchUpInside)

            view.addSubview(label)
            label.autoPinEdge(.top, to: .top, of: view, withOffset: Constants.vMargin)
            label.autoPinEdge(.bottom, to: .bottom, of: view, withOffset: -Constants.vMargin)
            label.autoPinEdge(.leading, to: .leading, of: view, withOffset: Constants.hMargin)
            label.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: -Constants.hMargin)

            self.addSubview(view)
            view.autoPinEdgesToSuperviewEdges()

            self.accessibilityLabel = CallStrings.joinCallPillButtonTitle
        }

        override public var bounds: CGRect {
            didSet {
                updateRadius()
            }
        }

        private func updateRadius() {
            layer.cornerRadius = bounds.size.height / 2
        }

        private enum Constants {
            static let vMargin: CGFloat = 4
            static let hMargin: CGFloat = 12
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private let callLink: CallLink
    private let callName: String

    init(
        callLink: CallLink,
        callName: String,
        joinAction: @escaping () -> Void
    ) {
        self.callLink = callLink
        self.callName = callName
        self.joinButton = JoinButton(joinAction: joinAction)

        super.init(frame: .zero)

        let stackView = UIStackView()
        stackView.addArrangedSubviews([iconView, textStack, joinButton])
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        stackView.alignment = .center
        stackView.spacing = Constants.spacingIconToText
        stackView.setCustomSpacing(Constants.spacingTextToButton, after: textStack)

        self.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private enum Constants {
        static let spacingTextToButton: CGFloat = 16
        static let spacingIconToText: CGFloat = 12
        static let textStackSpacing: CGFloat = 2

        static let circleViewDimension: CGFloat = CommonCallLinksUI.Constants.circleViewDimension
    }
}
