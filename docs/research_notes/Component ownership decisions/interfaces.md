# Bindings and folder-format adapters

Research date: 2026-09-27. These choices complete the host interfaces in the
[architecture](../../ARCHITECTURE.md). They are implementation plans, not
claims that the current bindings already use them.

## Generated bindings own the web representation

Select Emscripten 4.0.7 Embind and `--emit-tsd` for web command bindings.
Embind binds value objects, vectors, functions, and typed memory views and
generates their TypeScript declarations. Swift imports the engine's C ABI
through Clang. Both bindings call the current engine commands.
[Embind API](https://emscripten.org/docs/porting/connecting_cpp_and_javascript/embind.html),
[pinned binding implementation](https://github.com/emscripten-core/emscripten/blob/4.0.7/system/include/emscripten/bind.h).

The current handwritten TypeScript struct-offset mapping duplicates the C
layout contract. Embind owns that representation. The app supplies command
names, sample fields, and batch lifetime; it copies returned file bytes before
the native allocation expires. Raw typed views have native-memory lifetime,
not automatic ownership. Explicit registered types keep the generated API
typed. This boundary follows the need to send pen batches and notebook bytes
between the chosen engine and hosts; it adds no editor mechanism.

## Existing parsers own notebook syntax

Use the current Math Notes document model with pugixml 1.16 for page SVG,
InkML, and namespaced metadata, and
nlohmann-json from vcpkg baseline
`10541e317a660f4165ba4ac2851ab54a8d4577b1` for notebook JSON.
These are syntax owners. The adapter supplies only the documented field
mapping, path identity, original trace retention, and deterministic attribute
order. It updates the same current document model.
[pugixml manual](https://pugixml.org/docs/manual.html),
[nlohmann-json API](https://json.nlohmann.me/api/basic_json/),
[pinned vcpkg baseline](https://github.com/microsoft/vcpkg/blob/10541e317a660f4165ba4ac2851ab54a8d4577b1/versions/baseline.json).

Complete-editor alternatives are recorded for post-v1 review in
[ink.md](ink.md). The library parser handles syntax; the notebook contract
requires retaining `mn:` fields, raw InkML samples, and authored figure files.

## Platform file operations keep their actual guarantees

Use File System Access `createWritable`/`write`/`close` for browser per-file
replacement and NSFileCoordinator for native provider writes. A save is
acknowledged only after all required file operations finish. Persist new
assets before pages that reference them, and pages before notebook metadata
that lists them. Keep failed operations dirty and report the failure. On
reopen, the existing unlisted-page and invalid-source rules preserve files
left by an interrupted save. Neither browser file replacement nor this
ordering provides a transaction across the whole folder.
[browser file API](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access),
[Apple coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator).

For browser directory moves, select copy, byte-verify, then remove the source
only after successful verification. A failed copy leaves the source intact
and reports the partial destination. The inspected File System Access API
does not support directory `move`; native FileManager provides the operation
under file coordination. This is a folder-format adapter around platform
operations, not a sync engine.
[documented move restriction](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access#renaming-and-moving-files-and-folders).

Before replacing a loaded file, compare its current bytes with the saved base;
a detected external edit enters the existing conflict workflow. Browser File
System Access exposes no compare-and-swap against an external file provider.
The comparison therefore does not establish protection against an external
write between the check and replacement. This limit must remain visible in
the product contract; a stronger concurrent-writer guarantee needs a storage
authority with conditional writes, not more comparison code.

## Search record

Exact searches: `site:emscripten.org docs embind TypeScript emit-tsd typed_memory_view`;
`site:developer.chrome.com file system access filehandle move directories supported`.
Source inspection also covered the existing C ABI, engine dependency manifest,
and the primary parser APIs linked above.
