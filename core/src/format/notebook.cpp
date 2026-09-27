#include "format/notebook.h"

#include <algorithm>
#include <cstdio>
#include <set>

#include <nlohmann/json.hpp>

#include "format/page_svg.h"

namespace ink_engine {
namespace {

using Json = nlohmann::ordered_json;

std::vector<std::string> LayerIds(const Notebook &notebook) {
  std::vector<std::string> ids;
  for (const Layer &layer : notebook.layers) ids.push_back(layer.id);
  return ids;
}

bool IsPageFile(const std::string &path) {
  return path.starts_with("pages/") && path.ends_with(".svg") &&
         path.find('/', 6) == std::string::npos;
}

void FigureAssets(const Elements &elements, std::set<std::string> &paths) {
  for (const auto &box : elements) {
    if (const auto *figure = std::get_if<Figure>(&box->value)) {
      const std::string prefix = "../assets/" + figure->id;
      if (figure->scene_href == prefix + ".scene.json") {
        paths.insert("assets/" + figure->id + ".scene.json");
      }
      if (figure->tikz_href == prefix + ".tikz") {
        paths.insert("assets/" + figure->id + ".tikz");
      }
      FigureAssets(figure->children, paths);
    } else if (const auto *group = std::get_if<Bookmark>(&box->value)) {
      FigureAssets(group->children, paths);
    } else if (const auto *link = std::get_if<Link>(&box->value)) {
      FigureAssets(link->children, paths);
    }
  }
}

std::set<std::string> CollectFigureAssets(const Document &document) {
  std::set<std::string> paths;
  for (const auto &page : document.pages) {
    if (page->error) continue;
    for (const LayerContent &layer : page->layers) FigureAssets(layer.elements, paths);
  }
  return paths;
}

Json PageSizeJson(const PageSize &size) {
  if (auto *name = std::get_if<std::string>(&size)) return *name;
  auto [w, h] = std::get<std::array<double, 2>>(size);
  return Json::array({w, h});
}

PageSize ReadPageSize(const Json &json) {
  if (json.is_array() && json.size() == 2) {
    return std::array<double, 2>{json[0].get<double>(), json[1].get<double>()};
  }
  return json.is_string() ? json.get<std::string>() : std::string("A4");
}

}  // namespace

std::set<std::string> FigureAssetPaths(const Document &document) {
  return CollectFigureAssets(document);
}

Document ReadNotebookJson(std::string_view bytes) {
  Document document;
  Json json = Json::parse(bytes);
  Notebook &nb = document.notebook;
  nb.title = json.value("title", "");
  nb.page_size = ReadPageSize(json.value("pageSize", Json("A4")));
  nb.template_name = json.value("template", "");
  for (const Json &layer : json.value("layers", Json::array())) {
    nb.layers.push_back({layer.value("id", ""), layer.value("name", ""),
                         layer.value("hidden", false), layer.value("locked", false)});
  }
  for (const Json &page : json.value("pages", Json::array())) {
    Page listed{.id = page.value("id", ""), .file = page.value("file", ""),
                .error = "missing file"};
    document.pages = std::move(document.pages).push_back(immer::box<Page>(std::move(listed)));
  }
  return document;
}

const Page &AddPage(Document &document, const std::string &file, std::string_view bytes) {
  Page page = ReadPage(bytes, file, LayerIds(document.notebook));
  for (size_t i = 0; i < document.pages.size(); ++i) {
    const Page &listed = *document.pages[i];
    if (listed.unlisted || listed.file != file) continue;
    if (page.id.empty()) page.id = listed.id;
    document.pages = document.pages.set(i, immer::box<Page>(std::move(page)));
    return *document.pages[i];
  }
  // Unlisted pages follow the listed ones, sorted by file name.
  page.unlisted = true;
  size_t at = document.pages.size();
  while (at > 0 && document.pages[at - 1]->unlisted && document.pages[at - 1]->file > file) --at;
  document.pages = document.pages.insert(at, immer::box<Page>(std::move(page)));
  return *document.pages[at];
}

Document LoadNotebook(const NotebookFiles &files) {
  auto notebook_json = files.find("notebook.json");
  Document document =
      notebook_json == files.end() ? Document{} : ReadNotebookJson(notebook_json->second);
  std::set<std::string> listed;
  for (const auto &page : document.pages) listed.insert(page->file);
  for (const auto &[path, bytes] : files) {
    if (listed.contains(path) || IsPageFile(path)) AddPage(document, path, bytes);
  }
  return document;
}

std::string WriteNotebookJson(const Document &document) {
  const Notebook &nb = document.notebook;
  Json json;
  json["format"] = "math-notes";
  json["version"] = 1;
  json["title"] = nb.title;
  json["pageSize"] = PageSizeJson(nb.page_size);
  json["template"] = nb.template_name;
  json["layers"] = Json::array();
  for (const Layer &layer : nb.layers) {
    json["layers"].push_back(
        {{"id", layer.id}, {"name", layer.name}, {"hidden", layer.hidden}, {"locked", layer.locked}});
  }
  json["pages"] = Json::array();
  for (const auto &page : document.pages) {
    if (page->unlisted) continue;
    json["pages"].push_back({{"id", page->id}, {"file", page->file}});
  }
  return json.dump(2) + "\n";
}

NotebookFiles ChangedFiles(const Document &current, const Document *saved) {
  NotebookFiles changed;
  std::set<const Page *> saved_pages;
  if (saved) {
    for (const auto &page : saved->pages) saved_pages.insert(&page.get());
  }
  for (const auto &page : current.pages) {
    if (page->error || saved_pages.contains(&page.get())) continue;
    changed[page->file] = WritePage(*page);
  }
  std::string json = WriteNotebookJson(current);
  if (!saved || json != WriteNotebookJson(*saved)) changed["notebook.json"] = json;
  return changed;
}

std::vector<std::string> RemovedFiles(const Document &current, const Document *saved) {
  std::vector<std::string> removed;
  if (!saved) return removed;
  std::set<std::string> kept;
  for (const auto &page : current.pages) kept.insert(page->file);
  for (const auto &page : saved->pages) {
    if (!page->error && !kept.contains(page->file)) removed.push_back(page->file);
  }
  const std::set<std::string> current_assets = FigureAssetPaths(current);
  for (const std::string &path : FigureAssetPaths(*saved)) {
    if (!current_assets.contains(path)) removed.push_back(path);
  }
  return removed;
}

NotebookFiles AllFiles(const Document &document) { return ChangedFiles(document, nullptr); }

std::string NextPageFile(const Document &document) {
  int highest = 0;
  for (const auto &page : document.pages) {
    int number = 0;
    if (std::sscanf(page->file.c_str(), "pages/%d.svg", &number) == 1) {
      highest = std::max(highest, number);
    }
  }
  char name[32];
  std::snprintf(name, sizeof name, "pages/%04d.svg", highest + 1);
  return name;
}

}  // namespace ink_engine
