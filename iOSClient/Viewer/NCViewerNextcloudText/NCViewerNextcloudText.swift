// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-FileCopyrightText: 2019 Marino Faggiana
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import NextcloudKit
@preconcurrency import WebKit

class NCViewerNextcloudText: UIViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var webView = WKWebView()
    var bottomConstraint: NSLayoutConstraint?
    var link: String = ""
    var editor: String = ""
    var metadata: tableMetadata = tableMetadata()
    var imageIcon: UIImage?
    let utility = NCUtility()
    var items: [UIBarButtonItem] = []
    var didEncounterLoadingError = false
    var loadingTimeoutInterval: TimeInterval = 10.0
    var loadingTimeoutTimer: Timer?
    var editorHasLoaded = false
    var sessionRecoveryInterval: TimeInterval = 3.0
    var serverProbeInterval: TimeInterval = 15.0
    private var serverProbeTimer: Timer?

    @MainActor
    var controller: NCMainTabBarController? {
        self.tabBarController as? NCMainTabBarController
    }

    var sceneIdentifier: String {
        (self.tabBarController as? NCMainTabBarController)?.sceneIdentifier ?? ""
    }

    // MARK: - View Life Cycle

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if !metadata.ocId.hasPrefix("TEMP") {
            let moreButton = UIBarButtonItem(
                image: NCImageCache.shared.getImageButtonMore(),
                primaryAction: nil,
                menu: UIMenu(title: "", children: [
                    UIDeferredMenuElement.uncached { [self] completion in
                        if let menu = NCContextMenuViewer(metadata: self.metadata, controller: self.tabBarController as? NCMainTabBarController, webView: true, sender: self).viewMenu() {
                            completion(menu.children)
                        }
                    }
                ]))

            items.append(moreButton)
        }

        let group = UIBarButtonItemGroup(
            barButtonItems: items,
            representativeItem: nil
        )
        navigationItem.trailingItemGroups = [group]
        navigationItem.leftBarButtonItems = nil

        // Prevent back navigation gesture of iOS/iPadOS >= 26 as that will interfere with the possibility to mark text in onlyoffice
        if #available(iOS 26.0, *) {
            navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = false
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let contentController = config.userContentController
        contentController.add(self, name: "DirectEditingMobileInterface")
        if editor == "onlyoffice" {
            let dropSharedWorkersScript = WKUserScript(source: "delete window.SharedWorker;", injectionTime: WKUserScriptInjectionTime.atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(dropSharedWorkersScript)
        }
        webView = WKWebView(frame: CGRect.zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.isScrollEnabled = false
        view.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 0).isActive = true
        webView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor, constant: 0).isActive = true
        webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0).isActive = true
        bottomConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        bottomConstraint?.isActive = true

        if editor == "onlyoffice" {
            webView.customUserAgent = utility.getCustomUserAgentOnlyOffice()
        } else if editor == "nextcloud text" {
            webView.customUserAgent = utility.getCustomUserAgentNCText()
        } // else: use default

        if let url = URL(string: link) {
            var request = URLRequest(url: url)
            request.addValue("true", forHTTPHeaderField: "OCS-APIRequest")
            let language = NSLocale.preferredLanguages[0] as String
            request.addValue(language, forHTTPHeaderField: "Accept-Language")

            webView.load(request)
        }
    }

    deinit {
        print("dealloc")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: true)
        } else {
            tabBarController?.tabBar.isHidden = true
        }

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(networkReachabilityChanged), name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterNetworkReachability), object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            await NCNetworking.shared.transferDispatcher.addDelegate(self)
        }

        NCActivityIndicator.shared.start(backgroundView: view)
        startServerProbe()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(false, animated: true)
        } else {
            tabBarController?.tabBar.isHidden = false
        }

        Task {
            await NCNetworking.shared.transferDispatcher.removeDelegate(self)
        }

        webView.configuration.userContentController.removeScriptMessageHandler(forName: "DirectEditingMobileInterface")

        stopServerProbe()

        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: NCGlobal.shared.notificationCenterNetworkReachability), object: nil)
    }

    @objc func viewUnload() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - NotificationCenter

    @objc func keyboardWillChangeFrame(notification: Notification) {
        guard let info = notification.userInfo,
              let endFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let keyboardFrameInView = view.convert(endFrame.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrameInView.minY)
        bottomConstraint?.constant = -overlap
    }

    @objc func appDidBecomeActive() {
        guard editorHasLoaded, !didEncounterLoadingError else { return }
        checkSessionHealth()
    }

    @objc func networkReachabilityChanged() {
        guard !NCNetworking.shared.isOnline else { return }
        swapToLocalEditor()
    }

    private func swapToLocalEditor() {
        let utilityFileSystem = NCUtilityFileSystem()
        guard utilityFileSystem.fileProviderStorageExists(metadata) else { return }
        guard let nav = navigationController,
              let index = nav.viewControllers.lastIndex(where: { $0 === self }) else { return }

        let filePath = utilityFileSystem.getDirectoryProviderStorageOcId(metadata.ocId,
                                                                         fileName: metadata.fileNameView,
                                                                         userId: metadata.userId,
                                                                         urlBase: metadata.urlBase)
        let local = NCViewerTextEditor(filePath: filePath, metadata: metadata)
        local.navigationItem.setBidiSafeTitle(metadata.fileNameView)
        var stack = nav.viewControllers
        stack[index] = local
        nav.setViewControllers(stack, animated: false)
    }

    private func startServerProbe() {
        stopServerProbe()
        serverProbeTimer = Timer.scheduledTimer(withTimeInterval: serverProbeInterval, repeats: true) { [weak self] _ in
            self?.probeServer()
        }
    }

    private func stopServerProbe() {
        serverProbeTimer?.invalidate()
        serverProbeTimer = nil
    }

    private func probeServer() {
        guard editorHasLoaded else { return }
        guard let url = URL(string: metadata.urlBase + "/status.php") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let reachable = error == nil && (response as? HTTPURLResponse).map { $0.statusCode < 500 } ?? false
                if !reachable {
                    self.swapToLocalEditor()
                }
            }
        }.resume()
    }

    private func checkSessionHealth() {
        Task { @MainActor in
            let isAlive = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                var resumed = false
                webView.evaluateJavaScript("document.readyState") { result, error in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: error == nil && result != nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + sessionRecoveryInterval) {
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: false)
                }
            }
            if !isAlive {
                handleSessionExpired()
            }
        }
    }

    private func handleSessionExpired() {
        didEncounterLoadingError = true
        let windowScene = SceneManager.shared.getWindowScene(controller: controller)
        Task {
            await showErrorBanner(windowScene: windowScene, text: NSLocalizedString("_editor_session_expired_", comment: ""), errorCode: 0)
        }
    }

    // MARK: -

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "DirectEditingMobileInterface" {
            if message.body as? String == "close" {
                viewUnload()
            }

            if message.body as? String == "share" {
                NCCreate().createShare(controller: self.controller,
                                       metadata: metadata, page: .sharing)
            }

            if message.body as? String == "loading" {
                print("loading")
            }

            if message.body as? String == "loaded" {
                print("loaded")
            }

            if message.body as? String == "paste" {
                self.paste(self)
            }
        }
    }

    // MARK: -

    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        DispatchQueue.global().async {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(Foundation.URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(URLSession.AuthChallengeDisposition.useCredential, nil)
            }
        }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("didStartProvisionalNavigation")
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        print("didReceiveServerRedirectForProvisionalNavigation")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadingTimeoutTimer?.invalidate()
        loadingTimeoutTimer = nil
        didEncounterLoadingError = false
        editorHasLoaded = true
        NCActivityIndicator.shared.stop()
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }
}

extension NCViewerNextcloudText: UINavigationControllerDelegate {
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)

        Task {
            if parent == nil {
                await NCNetworking.shared.transferDispatcher.notifyAllDelegates { delegate in
                    delegate.transferReloadDataSource(serverUrl: self.metadata.serverUrl, requestData: true, status: nil)
                }
            }
        }
    }
}

extension NCViewerNextcloudText: NCTransferDelegate {
    func transferReloadData(serverUrl: String?) { }

    func transferReloadDataSource(serverUrl: String?, requestData: Bool, status: Int?) { }

    func transferProgressDidUpdate(progress: Float, totalBytes: Int64, totalBytesExpected: Int64, fileName: String, serverUrl: String) { }

    func transferChange(status: String,
                        account: String,
                        fileName: String,
                        serverUrl: String,
                        selector: String?,
                        ocId: String,
                        destination: String?,
                        error: NKError) {
        Task {@MainActor in
            if status == NCGlobal.shared.networkingStatusFavorite,
               self.metadata.ocId == ocId,
               let metadata = await NCManageDatabase.shared.getMetadataFromOcIdAsync(ocId) {
                self.metadata = metadata
            }
        }
    }
}
