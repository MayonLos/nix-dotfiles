# Firefox

Installs Firefox with a managed dark theme policy, forced Dark Reader, blocked conflicting synchronized themes, and generated `userChrome.css` / `userContent.css` fallbacks. One template carries the shared palette and a comment-isolated new-tab stylesheet; the activation and Noctalia hook split those sections into separate managed blocks. The browser chrome follows the palette, while userContent styles are restricted to Firefox's `about:home` and `about:newtab` documents. The new-tab preferences retain search, show one row of up to eight frequent sites, and hide sponsored/story content. It reads `user.appearance` for fallback colors and contributes the `firefox` Noctalia integration ID; selecting an appearance is required by an assertion.

Vertical rows target 36px height with a 4px total gap. The approximately 208px sidebar width remains Firefox's native profile-controlled width so a saved user resize is preserved.

The feature owns the Firefox package/policies, the `about` and unknown URL handlers, and the `seedFirefoxProfileUi` activation that applies the generated stylesheets and startup preferences. `checks.nix` publicly exports the `firefox-ui` fixture check. `default.nix` and `resources/` are private implementation except for the test entry point used by that check. It does not own Firefox profile data or account state.

Removing the feature removes its package, policies, URL handler, and activation. Seeded preferences and the two marked stylesheet blocks remain in the existing profile. The activation does not delete Firefox profiles, bookmarks, history, credentials, manual CSS outside the markers, or other preferences; profile files remain user data. Symlinked CSS files/directories and incomplete or duplicate markers are refused.

`resources/test_firefox_ui.py FALLBACK_CSS` parses both generated stylesheets and exercises the seed and Noctalia hook against an isolated temporary Firefox profile. It never opens or changes the real profile. The public check obtains `FALLBACK_CSS` from the seed command in Home Manager activation data, so the fixture checks the exact palette output used by the configured system.

Firefox 158 keeps the search handoff placeholder inside its shadow tree at native opacity 0.54. Its final contrast is about 4.05:1 on the surface background even when the public text token uses brightFg; the public host variables do not expose opacity. Palette text contrast does not certify that native placeholder.
