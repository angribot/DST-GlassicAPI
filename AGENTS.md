## Game source

Find the local checkout of DST-scripts, the game's scripts ("游戏源码", "原版", "上游"), in the `workspace.library` entries of `.luarc.json` (machine-local, gitignored); ask if it is missing. Each commit is one game build, so its history shows upstream updates.

Target the latest game build.

## Terminology

Name game and mod content by its in-game string in the language you are writing, in replies as well as files: English from `STRINGS` (the game's `strings.lua`, this mod's `main/strings.lua`), other languages from the matching `.po` (the game's `languages/`, this mod's `languages/`). An empty `msgstr` means the game shows the English name.

## Mod environments

Bind an API function to the calling mod's env when it registers through a per-mod env function (`AddPrefabPostInit`, `AddRecipeToFilter`, …): take `mod_env` first and add the function to `ENV_API` in `modmain.lua`, so the game attributes failures to the caller and orders it by the caller's priority. Errors from callbacks that run later, such as event listeners, name the registering mod (`mod_env.modname`).

## Implementation

- Reach for vanilla interfaces and existing files first; add a helper, wrapper, component, or file only when none of them can hold the code.
- Guard only against states you can point to in the game source.

## Lua compatibility

Target DST's Lua 5.1 runtime plus `bit`, not LuaJIT extensions.

- Use Lua 5.1 syntax: no `goto`/labels, `\x`/`\z` escapes, floor division, or native bitwise operators. Use `bit` for bitwise operations.
- Use `unpack` and `loadstring` instead of `table.unpack` and string-based `load`. Pass arguments to `xpcall` through a closure.
- Use `table.concat` for repeated strings with separators and `math.log(x) / math.log(base)` for other logarithm bases. Lua 5.1 silently ignores the extra arguments to `string.rep` and `math.log`.
- Access standard globals missing from the mod environment through `GLOBAL`, including `unpack`, `coroutine`, and `loadstring`.
- Keep coroutine yields outside C-call boundaries, including `pcall`/`xpcall`, metamethods, `table.sort` comparators, and `gsub` callbacks.
- Avoid relying on cross-runtime `math.random` sequences or out-of-range `%d` formatting.
- Check syntax with `stylua --syntax Lua51 - < file > /dev/null`. It accepts `\x` escapes, so search for those separately.

## Testing

Verify changed behavior with a simulation in a temporary directory outside the repository (e.g. `mktemp -d`); the repository keeps no test files. Simulations run on LuaJIT and only approximate DST, so list the runtime-sensitive behavior left to check in-game.

## Release notes

Release notes live in the `changelog` variable of `modinfo.lua`; there is no CHANGELOG file.

- Each language block opens with the current release's entries and no heading, since `description` already prepends "更新内容:" / "Changes:".
- After a blank line, `最近更新：` / `Recent Changes:` lists earlier entries of the current minor series, newest first.
- Bump the version once the current one is published to the Workshop; ask if you cannot tell. The user picks X (major), Y (minor), or Z (patch); propose one if they did not.
- No bump: add the entries to the current release, leave Recent Changes as is, and commit them with the change they describe.
- Z bump (e.g. `4.2.13` → `4.2.14`): write the new entries at the top and move the previous release's entries to the top of Recent Changes. The first patch of a series creates that section. Recent Changes accumulates every entry since the minor release.
- X or Y bump (e.g. `4.1.1` → `4.2`, `3.4.5` → `4.0`): replace the whole changelog with this release's entries and drop Recent Changes.
- Commit a bump on its own as `chore: bump version to X.Y.Z`, title only.
- Keep Chinese and English in lockstep: same entries, same order, moved and dropped together.
- Write each entry as a mod-author-facing `- ` line describing the API's observable behavior.
- Write both languages in the simple present: `RecipeSortBefore/RecipeSortAfter要求a、b为不同的非空字符串` / `RecipeSortBefore/RecipeSortAfter require distinct, non-empty strings for a and b`. Chinese entries drop 了; English entries without a subject start with the base verb (`Keep filter indices in sync after recipe sorting`).
