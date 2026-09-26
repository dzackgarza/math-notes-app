# AGENTS.md

Read README.md (pipeline, layout) and TRAPS.md (known failures) first.

Work plan: the GitHub issue tree rooted at #11, one milestone per sub-issue. `uvx --from git+https://github.com/dzackgarza/itree itree next dzackgarza/math-notes-app` names the next work unit in tree order.

Implementation ownership: read [docs/ARCHITECTURE.md#component-ownership](docs/ARCHITECTURE.md#component-ownership) before changing a plan or implementation. An accepted implementation plan names its selected complete owners, pins, API boundaries, and exact product-specific adapters before work begins. Every custom behavior needs a linked ownership decision with actual dependency searches, candidate evidence, the exact integration gap, and a reason Math Notes must own it. Evaluate complete frameworks, SDKs, and forks, including large dependencies. The rule covers adapters, reference ports, existing custom code, and ink reflow. Standard application behavior belongs to its framework. Extending the core's responsibilities or building a custom subsystem requires the completed decision and explicit user approval. A feature specification alone grants neither. Device and format acceptance checks prove an already selected owner; they are not a later owner-selection step.

The selected replacement in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) uses one Write fork ink model, Skia SVG rendering, platform scroll/interaction components, and a complete TikZ editor/solver/TeX stack. The deployed code still uses the earlier document and brush implementation. The Write-fork replacement awaits explicit architecture approval; do not treat this planning choice as permission to migrate source.

Invariants:
- The IPA's `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleIdentifier`, and byte size must equal the `source.json` entry. The workflow checks all of these before and after publishing; keep those checks when editing it.
- Each release tag is immutable and never deleted; `source.json` download URLs point at the per-build tag.
- Bundle ID `dev.zack.mathnotes` is fixed. Changing it makes SideStore treat the app as new and uses a free-account App ID slot.
- CI holds no Apple credentials and does not sign. SideStore signs on the device.
- Swift cannot build on the Linux host; verify Swift changes through a CI run (`gh run watch`).

<!-- agent-memory:start -->
# Agent memory

This repository uses the central agent memory vault at `/home/dzack/.agent-memory-vault`.

Project memory key: `projects/github.com__dzackgarza__math-notes-app/index`.

Repository `.agents` and `.hermes` paths are symlinks to the same vault-owned project directory.

Before changing architecture, search both project and global memory:

```bash
agent-memory search --scope both "<task or subsystem>"
```

Record durable repo-specific lessons with:

```bash
agent-memory add --scope project --type decision --title <title> --content <content>
agent-memory add --scope project --type trap --title <title> --content <content>
agent-memory add --scope project --type advice --title <title> --content <content>
agent-memory add --scope project --type context --title <title> --content <content>
agent-memory add --scope project --type reference --title <title> --content <content>
```

Plan work is card-backed. Create and update plan cards with `agent-memory plan add` and `agent-memory plan update`, not `agent-memory add --type plan`.

Use `agent-memory retrieve <key>`, `agent-memory update <key>`, and `agent-memory delete <key>` for memory CRUD.

The vault should be committed at all times. Treat staged or unstaged vault changes as an ephemeral error state. Before normal memory work resumes, load the bundled vault-maintenance skill with `agent-memory maintain skill vault-maintenance` and follow its referenced check, repair, and commit workflows.

Move reusable lessons during maintenance with:

```bash
agent-memory maintain move <key> --to global/advice
```
<!-- agent-memory:end -->
