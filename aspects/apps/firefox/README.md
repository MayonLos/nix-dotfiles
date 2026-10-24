# Firefox

Installs Firefox with a managed dark theme policy, forced Dark Reader, blocked conflicting synchronized themes, and a generated userChrome fallback. It reads `user.appearance` for the fallback colors and contributes the `firefox` Noctalia integration ID; selecting an appearance is required by an assertion.

The feature owns the Firefox package/policies, the `about` and unknown URL handlers, and the `seedFirefoxProfileUi` activation that applies the generated chrome stylesheet. `default.nix` and `resources/` are private implementation. It does not own Firefox profile data or account state.

Removing the feature removes its package, policies, URL handler, and activation. The activation does not delete Firefox profiles, bookmarks, history, or credentials; profile files remain user data.
