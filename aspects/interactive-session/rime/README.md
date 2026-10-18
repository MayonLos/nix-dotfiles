# Rime technical vocabulary

The supplemental table contains a small set of programming/Nix, embedded,
nuclear-engineering, and Minecraft terms missing from the currently pinned
Rime-Ice tables. Rime-Ice already imports its base, extension, Tencent, and
miscellaneous dictionaries; this table is deliberately not another broad
general-purpose dictionary.

`rime_ice_technical.dict.yaml` explicitly lists the five pinned upstream
`cn_dicts/*` tables in their original order, then the `rime_ice` body and
`nixdotfiles_technical`. librime 1.16 does not recursively import a child's
`import_tables`, so importing only `rime_ice` would lose its Chinese tables.
When updating Rime-Ice, compare this list to its current dictionary header.
The schema selects that composed
dictionary, but sets `translator/user_dict: rime_ice` explicitly. Thus the
compiled vocabulary gains the supplemental entries while the learner keeps
using the existing `rime_ice.userdb`. `enable_user_dict` and
`enable_sentence` remain enabled. The supplemental entries use weight 100 so
they remain available without being pinned above common words; selecting a
term continues to teach the existing user dictionary.

Rime-Ice already provides English lookup, Chinese-English mixed terms,
`custom_phrase`, five candidates per page, and its correction filter. The
English reduction mode only moves a curated set of collision-prone English
spellings; it does not demote all English. Common fuzzy-initial/final rules
remain disabled. This table does not override `custom_phrase`, correction
rules, or user settings.

## Editing terms

Add only a specific, frequently used term that is missing from the pinned
upstream dictionaries. Use UTF-8 and tab-separated `phrase`, full pinyin, and
a modest frequency. Check the exact phrase against the pinned Rime-Ice tables
before adding it, so the supplemental list stays small and does not shadow
upstream weights. Keep English product names in the existing English or
mixed-language translators unless a Chinese phrase is actually missing.

## Data and isolated validation

The managed files are read-only Nix outputs. Do not edit or replace files in
`~/.local/share/fcitx5/rime` in place. Preserve `rime_ice.userdb`, Rime sync
data, `user.yaml`, `installation.yaml`, `custom_phrase`, and existing build
backups. Do not export or commit personal learned entries.

Before applying, validate using a separate temporary Rime user-data directory:
copy the pinned Rime-Ice package data and the two supplemental dictionary
files into that fixture, render `default.custom.yaml` and
`rime_ice.custom.yaml` from this module into the fixture, and run the Rime
deployer/translator against that fixture only. Confirm the compiled schema
loads both tables, the active translator points to `rime_ice_technical`, and
its `user_dict` remains `rime_ice`. Do not point the fixture at the real
`~/.local/share/fcitx5/rime` directory. Runtime candidate order and learner
continuity still require application-level verification after a separately
reviewed deployment.
