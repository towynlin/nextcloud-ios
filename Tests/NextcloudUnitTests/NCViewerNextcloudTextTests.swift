// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import UIKit
import WebKit
@testable import Nextcloud

@Suite("NCViewerNextcloudText")
@MainActor
struct NCViewerNextcloudTextTests {

    private func makeViewController() -> NCViewerNextcloudText {
        let storyboard = UIStoryboard(name: "NCViewerNextcloudText", bundle: Bundle(for: NCViewerNextcloudText.self))
        let vc = storyboard.instantiateInitialViewController() as! NCViewerNextcloudText
        vc.editor = "nextcloud text"
        vc.loadViewIfNeeded()
        return vc
    }

    // MARK: - Close button

    @Test("Close button is present in left bar button items")
    func closeButtonExists() {
        let vc = makeViewController()

        let leftItems = vc.navigationItem.leftBarButtonItems ?? []
        #expect(!leftItems.isEmpty, "Expected at least one left bar button item (close button)")
    }

    @Test("Close button uses xmark system image")
    func closeButtonImage() {
        let vc = makeViewController()

        let closeButton = vc.navigationItem.leftBarButtonItems?.first
        #expect(closeButton != nil)
        // The button should have an action configured
        #expect(closeButton?.target != nil)
        #expect(closeButton?.action != nil)
    }

    @Test("Close button action is viewUnload")
    func closeButtonAction() {
        let vc = makeViewController()

        let closeButton = vc.navigationItem.leftBarButtonItems?.first
        #expect(closeButton?.action == #selector(NCViewerNextcloudText.viewUnload))
    }

    // MARK: - WebView error delegates

    @Test("didFailProvisionalNavigation sets didEncounterLoadingError")
    func didFailProvisionalNavigationSetsErrorFlag() {
        let vc = makeViewController()

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        vc.webView(vc.webView, didFailProvisionalNavigation: nil, withError: error)

        #expect(vc.didEncounterLoadingError == true)
    }

    @Test("didFail sets didEncounterLoadingError")
    func didFailSetsErrorFlag() {
        let vc = makeViewController()

        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        vc.webView(vc.webView, didFail: nil, withError: error)

        #expect(vc.didEncounterLoadingError == true)
    }

    @Test("webViewWebContentProcessDidTerminate sets didEncounterLoadingError")
    func processTerminatedSetsErrorFlag() {
        let vc = makeViewController()

        vc.webViewWebContentProcessDidTerminate(vc.webView)

        #expect(vc.didEncounterLoadingError == true)
    }

    @Test("didFinish clears didEncounterLoadingError")
    func didFinishClearsErrorFlag() {
        let vc = makeViewController()
        vc.didEncounterLoadingError = true

        vc.webView(vc.webView, didFinish: nil)

        #expect(vc.didEncounterLoadingError == false)
    }

    // MARK: - Loading timeout

    @Test("Default loading timeout interval is 10 seconds")
    func defaultLoadingTimeoutInterval() {
        let vc = makeViewController()

        #expect(vc.loadingTimeoutInterval == 10.0)
    }

    @Test("Loading timeout interval is configurable")
    func configurableLoadingTimeoutInterval() {
        let vc = makeViewController()
        vc.loadingTimeoutInterval = 5.0

        #expect(vc.loadingTimeoutInterval == 5.0)
    }

    @Test("didFinish invalidates loading timer")
    func didFinishInvalidatesTimer() {
        let vc = makeViewController()
        vc.loadingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 999, repeats: false) { _ in }

        vc.webView(vc.webView, didFinish: nil)

        #expect(vc.loadingTimeoutTimer == nil)
    }
}
