// A notebook directory as bytes: notebook.json plus pages/*.svg
// (docs/FORMAT.md, Layout). The host reads and writes the files.
#pragma once

#include <map>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "document/document.h"

namespace ink_engine {

// Relative path -> bytes, e.g. "notebook.json", "pages/0001.svg".
using NotebookFiles = std::map<std::string, std::string>;

// Loads notebook.json and every pages/*.svg in `files`. Listed pages come in
// notebook.json order; files in pages/ that it does not list follow, marked
// unlisted. A page that does not parse becomes an error page.
Document LoadNotebook(const NotebookFiles &files);

// The notebook of notebook.json, each listed page a "missing file" error page
// until AddPage loads it. Throws nlohmann::json::parse_error on bad JSON.
Document ReadNotebookJson(std::string_view bytes);

// Loads one page file: into its listed place, or else after the listed
// pages, in file name order, marked unlisted.
const Page &AddPage(Document &document, const std::string &file, std::string_view bytes);

// The files that differ from `saved`: every page whose box is not the object
// in `saved`, and notebook.json when its bytes differ. Error pages are never
// written. `saved` is null for a notebook that was never saved.
NotebookFiles ChangedFiles(const Document &current, const Document *saved);

// Page files of `saved` that `current` no longer has: deleted pages, whose
// files the host removes. Error pages are never removed (FORMAT.md).
std::vector<std::string> RemovedFiles(const Document &current, const Document *saved);

// Scene and TikZ sidecars still referenced by page figures.
std::set<std::string> FigureAssetPaths(const Document &document);

// Every file of the notebook, for a first save.
NotebookFiles AllFiles(const Document &document);

std::string WriteNotebookJson(const Document &document);

// The next unused four-digit page file name, "pages/NNNN.svg".
std::string NextPageFile(const Document &document);

}  // namespace ink_engine
