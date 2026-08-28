# AGENTS.md — Routes (World of Warcraft addon)

Read this first. It exists so a fresh agent can be productive in minutes.

## What this is

Routes draws gathering/farming routes (herbs, ore, etc.) on the WoW worldmap and
minimap, and optimizes them as traveling-salesman problems. **The repo root IS
the addon** — `Routes.toc` is the manifest; there is no build system. Target
runtime is **Lua 5.1** (WoW's Lua), and the code is written to run across many
client generations (Classic Era → retail).

## File map

| Path | Purpose |
| --- | --- |
| `Routes.lua` | Main addon: AceConfig options UI, worldmap/minimap line drawing, taboo regions, route CRUD. Biggest file (~4k lines). |
| `TSP.lua` | Route solvers (Lin-Kernighan / ILS / ACO) + clustering. |
| `NodeSkill.lua` | Colored "min skill" suffix for herb/mining nodes in the Add tab (e.g. `Herbalism - Goldthorn (34) - 170`). |
| `Plugins/*.lua` | Data-source adapters: `GatherMate2`, `Gatherer`, `HandyNotes`, `GatherLite`. |
| `Modules/*.lua` | `AutoShow`, `TomTom`. |
| `Locales/*.lua` | `enUS` is the source of truth. Other locales are shells using the AceLocale untranslated convention (`L[key] = true`); the WowAce packager merges real translations. |
| `dist/Routes.zip` | Built addon package (committed). |
| `tools/build-zip.sh` | Builds + verifies + commits the zip. |

## Commands

```bash
# Full package build (verifies TOC/XML refs, writes dist/Routes.zip)
tools/build-zip.sh

# TOC/XML reference resolution check only (no deps, python3)
tools/verify.sh
```

**No `lua`/`luac` is installed in the sandbox.** To validate Lua:

- Syntax (fast): `npm install --no-save luaparse` then
  `node tools/luacheck.js Routes.lua TSP.lua ...` (BOM-stripping, Lua 5.1).
  `tools/verify.sh` runs this automatically when luaparse is present.
- Runtime (when needed): `fengari` (npm) + handwritten WoW API stubs
  (`LibStub`, `CreateFrame`, `GetSpellInfo`, …). Pattern: stub the minimum
  globals, `luaL_loadstring` the file under `pcall`, then call the function
  under test.

## Gotchas (learned the hard way — do not relearn these)

1. **TOC `## Interface` takes *interface* numbers, not build numbers.**
   `69109` was the Classic 1.15.9 *build*; the interface is `11509`.
2. **GatherMate2 node ids are NOT WoW item ids.** Herbs are 401+, ores 201+
   (see GatherMate2's `Constants.lua` `node_ids`). Never feed a GM2 node id
   into an item-tooltip API as an item id. Item ids are only for real item
   ids (see `Routes:GetNodeSkillSuffixFromItem`).
3. **Lua 5.1 only**: no `goto`, no `\z`, no bitwise ops, no `//`, string
   `format` is `%`-style. `(...) : format(...)` is used a lot.
4. **Multi-client code is probe-and-pcall.** When an API differs across
   clients, probe for existence and wrap calls in `pcall` (see `NodeSkill.lua`
   rank/tooltip probing as the canonical example).
5. **Locale files**: never add a key only to `enUS` — every locale file must
   define all keys or you get "Missing entry" warnings (AceLocale read-only
   metatable). New UI strings → add to all 9 locale files.
6. **Session branch discipline**: all work happens on the `arena/*` session
   branch; changes are delivered via PR to `master`. `tools/build-zip.sh`
   pushes the *current* branch — don't hardcode one.
7. **Background clustering must really be background.** The Cluster and
   Cluster + Optimize buttons run from AceConfig click handlers, so large-route
   clustering must yield before heavy setup and avoid unbounded O(n^3) work.
   Classic Era is especially prone to `script ran too long` / multi-minute
   stalls here.


## Agent workflow for changes

When changing addon code in Arena sessions:

1. Stay on the assigned `arena/*` session branch and push only that branch.
2. Run `tools/verify.sh` (or `bash tools/verify.sh` if the executable bit was lost) before publishing.
3. Rebuild the committed addon package with `tools/build-zip.sh` so `dist/Routes.zip` matches the source change.
4. Commit source/docs changes before building the zip; `tools/build-zip.sh` may create the separate dist zip commit and push the current branch.

## Client → interface number quick reference

| Client | Interface |
| --- | --- |
| Retail (Midnight 12.x) | 120005 / 120007 |
| Classic Era (1.15.8 / 1.15.9) | 11508 / 11509 |
| MoP Classic (5.5.x) | 50503 / 50504 |
| TBC Classic (2.5.x) | 20505 / 20506 |

## Debugging the skill feature

`/routes skilldebug [itemID]` prints a full diagnostic (client build, player
profession ranks, which API found them, tooltip probes) ending in a single
`=== SKILL RESULT ...` line meant to be pasted into a bug report.
