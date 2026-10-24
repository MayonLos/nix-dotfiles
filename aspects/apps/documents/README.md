# Documents

Installs document applications and chooses handlers for documents. The aspect contributes the `obsidian` and `zathura` Noctalia integration IDs, reads `user.appearance` for Zathura's font when present, and otherwise uses the renderer's fallback font.

Outputs include Obsidian, Zotero, Okular, LibreOffice, English spelling/hyphenation data, Zathura configuration, PDF MIME association, and the Markdown default application. Zathura's colors are supplied at runtime through Noctalia's generated `noctaliarc`; the local configuration preserves that file as the sole palette writer. The Markdown handler is an intentional exception to the generic GUI text editor default.

`default.nix` and `zathura.nix` are owned implementation files; all Nix files here are private. Removing the feature removes these package, MIME, and configuration declarations after activation. It does not delete Obsidian vaults, Zotero libraries, documents, or application history.
