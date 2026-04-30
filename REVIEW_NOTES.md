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

## Phase 3 — Session Recovery on App Resume (`claude/session-recovery-PV8gg`)

**Medium confidence.** The approach is sound but the JS probe has nuances.

### JS probe may give false positives

`document.readyState` checks whether the WebView's DOM is intact, not whether the Nextcloud Text *editor session* is still valid on the server. A stale page can return `"complete"` even if the editing WebSocket/polling connection has died. The editor might look loaded but be unable to save changes.

- [ ] Test: open editor, lock phone for 10+ minutes, unlock — does the probe catch a dead session?
- [ ] If not, consider probing with an editor-specific JS expression (e.g., checking if the Nextcloud Text editing API is responsive) instead of generic `document.readyState`
- [ ] For now, this is still an improvement: it catches hard crashes (WebView process killed) and full page failures, which are the most common cases

### Race condition on rapid foreground/background cycling

If the user rapidly switches apps, multiple `appDidBecomeActive` calls could fire while a previous `checkSessionHealth()` is still awaiting its probe. The `didEncounterLoadingError` guard prevents duplicate error banners after the first failure, but multiple concurrent JS evaluations could run.

- [ ] Acceptable for now — the worst case is redundant JS evaluations, not incorrect behavior

### Localization

- [ ] `_editor_session_expired_` will show English in non-English locales until translated via Transifex

## Phase 4 — "File was overwritten" warning on reopen after offline edit

**Known issue, deferred.** After editing offline and uploading, reopening the file in the Nextcloud Text editor shows a banner: *"The file was overwritten. Your current changes cannot be auto-saved. Please choose how to proceed."* with an "Overwrite the file and save the current changes" button.

### Why it happens

Nextcloud Text persists per-user document state server-side (the in-flight collaborative-editing buffer + last-known content hash). Our offline upload goes through plain WebDAV, which updates the file but not Text's session state. On reopen, Text loads its session state, fetches the file, sees they no longer match, and warns. This would happen for any external modification to a Text-edited file (desktop sync, API, another client) — it is not unique to this offline-edit flow.

The mid-session swap from web editor to local editor (when connectivity drops) probably makes it worse: the original Text WebSocket session is abandoned rather than gracefully closed, leaving more divergence for Text to detect on reopen.

### The footgun

The "Overwrite the file and save the current changes" button saves Text's *abandoned-session buffer* over the just-uploaded offline edits. Clicking it can clobber the offline work. Users should close the warning (or the editor) and reopen — the upload is already correct.

### What was checked

- `NextcloudKit` exposes `textOpenFile`, `textCreateFile`, `textObtainEditorDetails`, `textGetListOfTemplates` — **no `textCloseFile` or session-invalidation API**.
- `WKWebView` uses `WKWebsiteDataStore.nonPersistent()`, so this is not local browser storage; it is server-side state.
- The `directEditing/open` endpoint accepts an optional `fileId`. `NCViewer.swift` does not currently pass one.

### Options, in increasing effort

- [ ] **A. Accept and document.** Add an in-product note or release-notes entry warning users not to click "Overwrite" after an offline edit. Lowest effort, but lands a confusing-and-dangerous footgun on users.
- [ ] **B. Graceful WebView close before swap.** In `swapToLocalEditor()`, `evaluateJavaScript` to dispatch `pagehide`/`beforeunload` or programmatically click the editor's close button before replacing the view controller. Gives Text's frontend a chance to end its session cleanly. Speculative — may or may not cause Text to release the server-side session.
- [ ] **C. Pass `fileId` to `textOpenFileAsync`.** One-line change in `NCViewer.swift:135`. Unknown impact — Text *may* create a fresh session keyed by `fileId` rather than resuming a stale one. Cheap to try.
- [ ] **D. Implement `textCloseFile` (or equivalent) against the OCS endpoint.** Either upstream in NextcloudKit or call the raw HTTP endpoint inline. Real fix; requires identifying the correct server endpoint (Text's `/apps/text/session/close` or similar) and possibly upstreaming.

### Recommendation

Try **C** first (cheap, plausibly helpful), then **B** (low cost, plausibly helpful), and fall back to **A** if neither resolves it. Skip **D** unless this becomes a recurring complaint.
