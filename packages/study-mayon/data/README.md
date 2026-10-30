# Built-in dictionary source

`study-mayon` builds its optional exam vocabulary database from the public
[ECDICT repository](https://github.com/skywind3000/ECDICT), specifically
`ecdict.csv` at commit
[`ab22ad36302cafc6349a050e2b60894855208055`](https://github.com/skywind3000/ECDICT/commit/ab22ad36302cafc6349a050e2b60894855208055).
The upstream repository identifies itself as MIT licensed and describes the
CSV fields, including phonetic, English definition, Chinese translation,
exam tags and frequency. The source CSV SHA-256 is
`d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc`
(Nix SRI `sha256-0ey9+e4rkgr7b0MMpra7n1WViM8N/4bgS9JV+TkIQ8w=`).

The Nix package fetches that pinned CSV and runs `scripts/build_dictionary.py`
to create a small SQLite database. It retains words marked by ECDICT's `cet4`,
`cet6`, `ky`, `ielts`, `toefl`, or `gre` tags, with one row per word and raw
ECDICT book tag so a word may appear in several books. `frequency` is the negative ECDICT
rank, allowing `ORDER BY frequency DESC` to place common words first. The
importer does not add
independently sourced vocabulary or examples. The app's `roots` field contains
human-readable forms derived from ECDICT's `exchange` field (such as past tense,
plural, or lemma); these are inflections and lemma links, not etymological roots.
ECDICT's `detail` field currently does not provide reliable example sentences,
so examples remain empty unless supplied by an imported/user word list.

Only the generated subset is shipped; its rows remain ECDICT-derived data and
are covered by the upstream MIT license. Attribution and the upstream license
link are provided here. The dataset is optional and can be replaced by a
user-imported vocabulary collection.
