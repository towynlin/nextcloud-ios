# Review Notes — Offline Markdown Editing Changes

Critiques and concerns to validate on a Mac build, organized by confidence level.

## Phase 1 — Close Button + Error Recovery (`claude/fix-markdown-editing-PV8gg`)

**High confidence.** Straightforward UIKit changes. Minimal risk.

- [ ] Verify the close (X) button appears and works in both `nextcloud text` and `onlyoffice` editor modes
- [ ] Verify the 10-second timeout fires and shows the error banner
- [ ] Verify `webView:didFinish:` still cancels the timer and stops the spinner on successful loads
- [ ] Verify `_error_loading_editor_` localization key renders correctly (will show English fallback in other locales until translated via Transifex)

## Phase 2 — Local Text Editor + Offline Routing (`claude/local-text-editor-PV8gg`)

**Medium confidence.** Two concerns:

### Upload queueing creates a new file instead of updating

`queueUploadToServer()` follows the `NCViewerQuickLook` pattern: it generates a *new* `ocId`, copies the file to a new provider storage path, and creates new upload metadata. This means the server receives a **new file** rather than an update to the existing one. For offline editing, the expected behavior is to **overwrite** the original. Needs investigation:

- [ ] Test: edit an offline file, reconnect, verify whether the server shows a duplicate or an update
- [ ] If it creates a duplicate, change to reuse the existing `ocId` and overwrite in-place, or use a different upload selector

### Offline routing is a point-in-time check

`!NextcloudKit.shared.isNetworkReachable()` is checked once at the start of `getViewerController()`. If the network drops *after* this check passes and `textOpenFileAsync()` hangs, the user goes through the WebView path. Phase 1's timeout + close button prevent getting stuck, but the user won't get the local editor experience.

- [ ] Acceptable for now — revisit if users report issues
- [ ] A future improvement could add a timeout-based fallback in `NCViewer` itself

### Localization

- [ ] `_offline_editing_banner_` will show English in non-English locales until translated via Transifex

## Phase 2.5 — Runestone Integration (`claude/runestone-editor-PV8gg`)

**Lower confidence.** Built without a Swift toolchain — could not compile or test.

### API correctness (cannot verify without building)

- [ ] Confirm `Runestone.Theme` protocol matches the signatures used in `MarkdownEditorTheme`: `textColor(for rawHighlightName: String) -> UIColor?` and `fontTraits(for rawHighlightName: String) -> FontTraits`
- [ ] Confirm `TextViewState(text:theme:language:)` initializer exists in Runestone 0.5.x
- [ ] Confirm `TextView` has `.text` (read-write `String`), `.showLineNumbers`, `.isLineWrappingEnabled`, `.contentInset`, `.verticalScrollIndicatorInsets`
- [ ] Confirm `TreeSitterLanguage.markdown` is the correct extension name from the `RunestoneTreeSitterMarkdown` product in `TreeSitterLanguages`

### Syntax highlighting may be minimal

The `MarkdownEditorTheme` maps highlight names like `"keyword"`, `"string"`, `"comment"`. However, tree-sitter-markdown likely emits markdown-specific names like `markup.heading`, `markup.bold`, `markup.link.url`, `markup.raw`. The `HighlightName` initializer strips dot suffixes progressively, so `markup.heading` would try `markup.heading` → `markup` → no match → return nil → default color.

- [ ] Run the editor with `#if DEBUG` logging to see what highlight names tree-sitter-markdown actually produces
- [ ] Update `MarkdownEditorTheme.textColor(for:)` with the actual highlight names
- [ ] The editor will still work without this — just without meaningful syntax coloring

### SPM dependency weight

- [ ] Assess build time and binary size impact of Runestone + TreeSitterLanguages
- [ ] TreeSitterLanguages bundles 34 languages but only `RunestoneTreeSitterMarkdown` is linked — verify the linker tree-shakes unused languages

### Xcode project file

- [ ] The `project.pbxproj` edits were done by hand. Xcode may reformat or reorder entries on first open. This is cosmetic but may cause a noisy diff.
