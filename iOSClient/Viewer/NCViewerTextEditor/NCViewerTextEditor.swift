// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit

class NCViewerTextEditor: UIViewController {
    let textView = UITextView()
    private(set) var offlineBanner: UILabel?
    private let filePath: String
    private let metadata: tableMetadata
    private let utilityFileSystem = NCUtilityFileSystem()
    private let database = NCManageDatabase.shared

    init(filePath: String, metadata: tableMetadata) {
        self.filePath = filePath
        self.metadata = metadata
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupOfflineBanner()
        setupTextView()
        loadFile()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let closeButton = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(closeTapped))
        closeButton.accessibilityLabel = NSLocalizedString("_close_", comment: "")
        navigationItem.leftBarButtonItems = [closeButton]

        let saveButton = UIBarButtonItem(title: NSLocalizedString("_save_", comment: ""), style: .done, target: self, action: #selector(saveTapped))
        navigationItem.rightBarButtonItems = [saveButton]

        navigationItem.hidesBackButton = true
    }

    private func setupOfflineBanner() {
        let banner = UILabel()
        banner.text = NSLocalizedString("_offline_editing_banner_", comment: "")
        banner.textAlignment = .center
        banner.font = .preferredFont(forTextStyle: .footnote)
        banner.textColor = .secondaryLabel
        banner.backgroundColor = .secondarySystemBackground
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: 28)
        ])

        offlineBanner = banner
    }

    private func setupTextView() {
        textView.font = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .default
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: offlineBanner?.bottomAnchor ?? view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - File I/O

    private func loadFile() {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }
        textView.text = content
    }

    @discardableResult
    func saveFile() -> Bool {
        guard let text = textView.text else { return false }
        do {
            try text.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func queueUploadToServer() {
        let session = NCSession.shared.getSession(account: metadata.account)
        let ocId = NSUUID().uuidString
        let size = utilityFileSystem.getFileSize(filePath: filePath)
        let fileNamePath = utilityFileSystem.getDirectoryProviderStorageOcId(ocId, fileName: metadata.fileNameView, userId: metadata.userId, urlBase: metadata.urlBase)

        guard utilityFileSystem.copyFile(atPath: filePath, toPath: fileNamePath) else { return }

        Task { @MainActor in
            let metadataForUpload = await NCManageDatabaseCreateMetadata().createMetadataAsync(
                fileName: metadata.fileName,
                ocId: ocId,
                serverUrl: metadata.serverUrl,
                url: "",
                session: session,
                sceneIdentifier: nil)

            metadataForUpload.session = NCNetworking.shared.sessionUploadBackground
            metadataForUpload.sessionSelector = NCGlobal.shared.selectorUploadFileNODelete
            metadataForUpload.size = size
            metadataForUpload.status = NCGlobal.shared.metadataStatusWaitUpload
            metadataForUpload.sessionDate = Date()

            database.addMetadata(metadataForUpload)
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        if saveFile() {
            queueUploadToServer()
        }
        navigationController?.popViewController(animated: true)
    }

    @objc private func saveTapped() {
        if saveFile() {
            queueUploadToServer()
        }
    }

    // MARK: - Keyboard

    @objc private func keyboardWillShow(notification: Notification) {
        guard let frameInfo = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let height = frameInfo.cgRectValue.height
        textView.contentInset.bottom = height
        textView.verticalScrollIndicatorInsets.bottom = height
    }

    @objc private func keyboardWillHide(notification: Notification) {
        textView.contentInset.bottom = 0
        textView.verticalScrollIndicatorInsets.bottom = 0
    }
}
