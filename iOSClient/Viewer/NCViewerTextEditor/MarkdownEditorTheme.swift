// SPDX-FileCopyrightText: Nextcloud GmbH
// SPDX-License-Identifier: GPL-3.0-or-later

import UIKit
import Runestone

struct MarkdownEditorTheme: Theme {
    let font: UIFont = .monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
        weight: .regular
    )
    let textColor: UIColor = .label

    let gutterBackgroundColor: UIColor = .secondarySystemBackground
    let gutterHairlineColor: UIColor = .separator

    let lineNumberColor: UIColor = .tertiaryLabel
    let lineNumberFont: UIFont = .monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
        weight: .regular
    )

    let selectedLineBackgroundColor: UIColor = .systemFill
    let selectedLinesLineNumberColor: UIColor = .secondaryLabel
    let selectedLinesGutterBackgroundColor: UIColor = .tertiarySystemBackground

    let invisibleCharactersColor: UIColor = .quaternaryLabel

    let pageGuideHairlineColor: UIColor = .separator
    let pageGuideBackgroundColor: UIColor = .secondarySystemBackground

    let markedTextBackgroundColor: UIColor = .systemFill
    let markedTextBackgroundCornerRadius: CGFloat = 4

    func textColor(for rawHighlightName: String) -> UIColor? {
        switch rawHighlightName {
        case "keyword":
            return .systemPurple
        case "string":
            return .systemGreen
        case "comment":
            return .systemGray
        case "number":
            return .systemOrange
        case "operator", "punctuation":
            return .tertiaryLabel
        default:
            return nil
        }
    }

    func fontTraits(for rawHighlightName: String) -> FontTraits {
        switch rawHighlightName {
        case "keyword":
            return .bold
        default:
            return []
        }
    }
}
