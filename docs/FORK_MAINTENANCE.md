# Maintaining this fork

This guide describes how this personal fork tracks `Zelda64Recomp/Zelda64Recomp` while keeping fork-specific work, including macOS packaging, independent of upstream.

## Remote and branch layout

At the root of the repository:

- `origin` is `https://github.com/Zelda64Recomp/Zelda64Recomp.git` (upstream).
- `fork` is `git@github.com:mabino/Zelda64Recomp.git` (your writable fork).
- `dev` is the working branch and tracks `fork/dev`.

The GitHub Actions workflow `Upstream sync` checks upstream `dev` weekly and can also be started from the Actions tab. For ordinary root-level changes, it creates or updates a pull request from `automation/upstream-dev` into your `dev` branch. Review and merge that pull request yourself. The workflow does not publish to upstream or merge automatically.

Enable Actions on the fork for the scheduled workflow to run. The workflow requests repository write access for contents, issues, and pull requests so it can push its review branch and report blocked syncs.

The workflow pauses for human review if upstream changes `.gitmodules`, changes any submodule gitlink, or cannot be merged cleanly. It creates an issue with the reason and relevant commits. This protects the fork's dependency URLs and ensures each referenced submodule commit is available from a repository that users can clone.

## Syncing manually

For a normal root-level sync:

```sh
git switch dev
git fetch origin dev
git merge --no-ff origin/dev
git push fork dev
```

Resolve any conflicts and review the result before pushing. Keep fork-specific changes, such as macOS packaging and save-path behavior, as commits on `dev` or on topic branches merged into `dev`. Avoid rebasing or force-pushing the published `dev` branch.

For future platform-specific work, favor dedicated files and platform-gated CMake logic (for example, macOS bundle and signing steps under `.github/macos/` and `if(APPLE)` blocks) over changes to shared runtime code. Keep changes that must touch shared files in small, clearly named commits. The upstream-sync pull request then brings upstream history into the fork branch while preserving those fork commits for review.

## Updating forked submodules

The root `.gitmodules` points RT64 and N64ModernRuntime at your forks. Those projects contain nested submodules, and their `.gitmodules` files also point the modified nested dependencies at your forks. Preserve these URLs for dependencies whose commits differ from upstream; otherwise a fresh recursive clone may not be able to fetch the recorded commit.

Each modified submodule uses `origin` for its upstream repository and `fork` for your fork. Merge upstream changes into the existing `codex/macos-compatibility` branch, then push that branch to your fork. For example, from a submodule directory:

```sh
git fetch origin
git switch codex/macos-compatibility
git merge --no-ff origin/main   # use the appropriate upstream branch
git push fork codex/macos-compatibility
```

Check the submodule's upstream default branch before merging; it may be `main` or `master`. Do not replace a submodule's fork URL with the upstream URL if the parent records a commit that exists only on your fork.

Update nested dependencies from the leaves upward so every parent points to a commit already pushed to its fork:

- RT64 chain: update and push `hlslpp`, then update and push RT64, then update the root's RT64 pointer.
- Runtime chain: update and push `fmt`, then update and push N64Recomp, then update and push N64ModernRuntime, then update the root's runtime pointer.

At each parent, stage the changed submodule directory and commit the gitlink update. Push each fork branch before updating and pushing its parent. Finally push the root branch to `fork/dev`. The weekly workflow deliberately does not automate this chain.

## Upstream changes that touch submodules

When an upstream sync issue reports a `.gitmodules` or gitlink change, inspect the upstream commit range and handle each affected dependency manually. Confirm the target commit is present on your fork (or push it there), update nested pointers from leaves to parents, preserve the fork URLs, then merge the upstream root changes and commit the corrected gitlinks. Once the dependency chain is cloneable, close the issue and push `dev`.
