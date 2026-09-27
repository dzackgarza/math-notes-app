# AGENTS.md

Read README.md (pipeline, layout) and TRAPS.md (known failures) first.

Before the first usable v1, work directly on `main`. Complete the web app
first: build its full UI, connect the specified features, and resolve their
product-level failures in the deployed browser. Then write end-to-end tests
for user stories. Add narrower tests when the architecture they would test
is substantially present. Port the working web product to iPad after that.
The GitHub issue tree rooted at #11 records requirements and gaps.

Implementation ownership: read [docs/ARCHITECTURE.md#component-ownership](docs/ARCHITECTURE.md#component-ownership) before changing a plan or implementation. Standard application behavior belongs to a mature framework or platform API, including scroll physics and edge motion; a missing standard detail is evidence to check the owner, not a custom feature request. Writing and editing notebook ink are reasonable app responsibilities. For a new domain capability, first seek a dependency that owns the whole problem, then a reference implementation. Only necessary residue with neither may use new ungrounded code. A new subsystem or expanded core boundary needs a linked decision with actual dependency searches, candidate evidence, the exact integration gap, and explicit user approval. Evaluate complete frameworks, SDKs, and forks, including large dependencies. An existing working domain capability does not require replacement merely because a broader dependency exists.

The v1 plan in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) uses the current Math Notes document and editing engine, Google Ink, Skia, platform scroll/interaction components, and the selected TikZ editor/solver/TeX stack. Assessing Write as a possible ink-engine owner is a post-v1 refactoring task. Write source and fixtures remain reference material for specific behavior.

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
