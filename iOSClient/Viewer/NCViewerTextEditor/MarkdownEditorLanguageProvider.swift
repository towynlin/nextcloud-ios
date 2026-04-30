// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import Runestone
import TreeSitterMarkdownInlineRunestone

final class MarkdownEditorLanguageProvider: TreeSitterLanguageProvider {
    func treeSitterLanguage(named languageName: String) -> TreeSitterLanguage? {
        languageName == "markdown_inline" ? .markdownInline : nil
    }
}
