// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import UIKit
@testable import Nextcloud

@Suite("NCViewerTextEditor")
@MainActor
struct NCViewerTextEditorTests {

    private func makeTempFile(content: String = "# Hello\n\nWorld") -> String {
        let path = NSTemporaryDirectory() + UUID().uuidString + ".md"
        try! content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private func makeEditor(filePath: String? = nil) -> NCViewerTextEditor {
        let path = filePath ?? makeTempFile()
        let vc = NCViewerTextEditor(filePath: path, metadata: tableMetadata())
        vc.loadViewIfNeeded()
        return vc
    }

    // MARK: - Initialization

    @Test("Loads file content into text view")
    func loadsFileContent() {
        let content = "# Test Content\n\nSome text here."
        let path = makeTempFile(content: content)
        let vc = makeEditor(filePath: path)

        #expect(vc.textView.text == content)
    }

    @Test("Handles empty file")
    func handlesEmptyFile() {
        let path = makeTempFile(content: "")
        let vc = makeEditor(filePath: path)

        #expect(vc.textView.text == "")
    }

    // MARK: - Navigation bar

    @Test("Has close button in left bar button items")
    func hasCloseButton() {
        let vc = makeEditor()

        let leftItems = vc.navigationItem.leftBarButtonItems ?? []
        #expect(!leftItems.isEmpty)
    }

    @Test("Has save button in right bar button items")
    func hasSaveButton() {
        let vc = makeEditor()

        let rightItems = vc.navigationItem.rightBarButtonItems ?? []
        #expect(!rightItems.isEmpty)
    }

    // MARK: - Saving

    @Test("Save writes content back to file")
    func saveWritesToFile() {
        let path = makeTempFile(content: "original")
        let vc = makeEditor(filePath: path)

        vc.textView.text = "modified content"
        vc.saveFile()

        let saved = try! String(contentsOfFile: path, encoding: .utf8)
        #expect(saved == "modified content")
    }

    @Test("Save returns true on success")
    func saveReturnsTrue() {
        let path = makeTempFile(content: "test")
        let vc = makeEditor(filePath: path)

        #expect(vc.saveFile() == true)
    }

    @Test("Save returns false for invalid path")
    func saveReturnsFalseForBadPath() {
        let vc = NCViewerTextEditor(filePath: "/nonexistent/path/file.md", metadata: tableMetadata())
        vc.loadViewIfNeeded()

        #expect(vc.saveFile() == false)
    }

    // MARK: - Offline banner

    @Test("Shows offline banner view")
    func showsOfflineBanner() {
        let vc = makeEditor()

        #expect(vc.offlineBanner != nil)
        #expect(vc.offlineBanner?.isHidden == false)
    }
}
