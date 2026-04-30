// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import Runestone

final class MarkdownEditorTheme: Theme {
    let font: UIFont = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    let textColor: UIColor = NCBrandColor.shared.textColor

    let gutterBackgroundColor: UIColor = .secondarySystemBackground
    let gutterHairlineColor: UIColor = .separator

    let lineNumberColor: UIColor = .secondaryLabel
    let lineNumberFont: UIFont = .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)

    let selectedLineBackgroundColor: UIColor = .tertiarySystemBackground
    let selectedLinesLineNumberColor: UIColor = .label
    let selectedLinesGutterBackgroundColor: UIColor = .secondarySystemBackground

    let invisibleCharactersColor: UIColor = .tertiaryLabel

    let pageGuideHairlineColor: UIColor = .tertiaryLabel
    let pageGuideBackgroundColor: UIColor = .secondarySystemBackground

    let markedTextBackgroundColor: UIColor = NCBrandColor.shared.customer.withAlphaComponent(0.2)

    func textColor(for highlightName: String) -> UIColor? {
        switch highlightName {
        case "text.title":
            return NCBrandColor.shared.customer
        case "text.literal":
            return NCBrandColor.shared.presentationIconColor
        case "text.uri", "text.reference":
            return NCBrandColor.shared.documentIconColor
        case "punctuation.special", "punctuation.delimiter", "string.escape":
            return NCBrandColor.shared.textColor2
        default:
            return nil
        }
    }

    func fontTraits(for highlightName: String) -> FontTraits {
        switch highlightName {
        case "text.title", "text.strong":
            return .bold
        case "text.emphasis":
            return .italic
        default:
            return []
        }
    }
}
