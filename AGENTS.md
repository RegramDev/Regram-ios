# Regram repository guidance

- Start with [README.md](README.md) and [docs/README.md](docs/README.md). Treat docs/superpowers as historical notes, not current build or release instructions.
- The app target is **//Telegram:Regram**. Local API credentials, signing material and generated build configuration belong in ignored **build-input/**; never add them, IPA files or real account data to a commit.
- Preserve unrelated worktree changes. Regram-owned modules live in **Regram/**. When changing Telegram upstream sources, keep the patch narrow and mark it **MARK: Regram**.
- Run checks relevant to the edit. For UI or behavior changes, explain what was compiled, what was exercised on a device, and what remains unverified.
- The rules_apple checkout may show local changes after applying the tracked compatibility patch. See [build-system/patches/README.md](build-system/patches/README.md) before touching that submodule.
- Use [docs/lcsign-reference-packaging.md](docs/lcsign-reference-packaging.md) for ad-hoc reference IPA packaging. It describes a reusable process; it does not contain personal signing credentials or a current release artifact.
