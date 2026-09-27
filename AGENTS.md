# AGENTS.md

Read README.md (pipeline, layout) and TRAPS.md (known failures) first.

Before the first usable v1, work directly on `main` and commit integrated
product slices there. The GitHub issue tree rooted at #11 records requirements
and gaps. Choose work by what the end-to-end app needs next. Keep the web and
iPad hosts, shared engine, and notebook files working together as each slice
lands. The repository's CI and local deployment verify those slices.

Invariants:
- The IPA's `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleIdentifier`, and byte size must equal the `source.json` entry. The workflow checks all of these before and after publishing; keep those checks when editing it.
- Each release tag is immutable and never deleted; `source.json` download URLs point at the per-build tag.
- Bundle ID `dev.zack.mathnotes` is fixed. Changing it makes SideStore treat the app as new and uses a free-account App ID slot.
- CI holds no Apple credentials and does not sign. SideStore signs on the device.
- Swift cannot build on the Linux host; verify Swift changes through a CI run (`gh run watch`).
