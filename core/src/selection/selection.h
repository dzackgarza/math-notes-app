// Selection geometry: which elements a lasso or a rectangle selects, the
// selection rectangle and its handles, transforms of selected elements, and
// the clipboard document.
//
// Ports Write (styluslabs/Write 401b65d) syncscribble/selection.cpp:
// LassoSelector::addPoint (1105-1154), RectSelector::selectHit (691-699),
// RectSelector::shrink (727-741), scaleHandleHit and rotHandleHit (748-778);
// and scribblearea.cpp selectionHit (1345-1377). The lasso hit test is
// google/ink's (1b220eee): the closed lasso mesh of
// ink/strokes/internal/jni/mesh_creation_native.cc:56-110 (geometry/hit_shapes.h)
// and PartitionedMesh::CoverageIsGreaterThan (ink/geometry/partitioned_mesh.h:299-331).
#pragma once

#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "document/document.h"
#include "document/ids.h"
#include "format/notebook.h"
#include "ink/geometry/partitioned_mesh.h"
#include "render/renderer.h"
#include "strokes/clip.h"

namespace ink_engine {

// Write ScribbleArea::MIN_LASSO_POINT_DIST (scribblearea.cpp:14): lasso
// points closer than this many view units to the last kept point are dropped.
inline constexpr double kLassoMinPointDistance = 2;
// Write's lasso simplification threshold, 0.5 view units (scribblearea.cpp:1566).
inline constexpr double kLassoSimplify = 0.5;
// google/ink coverage above which the lasso selects an element (#24).
inline constexpr float kLassoCoverage = 0.9f;
// Write RectSelector::HANDLE_SIZE and HANDLE_PAD, view units (selection.cpp:687-688).
inline constexpr double kHandleSize = 4;
inline constexpr double kHandlePad = 4;
// Write's minimum padding of the selection rectangle, 1 Write unit
// (1/150 inch), in pt (RectSelector::shrink).
inline constexpr double kSelectionMinPad = 0.48;
// Duplicate pastes the copy this far right of and below the original (#24).
inline constexpr double kDuplicateOffset = 10;

// The lasso's points in page coordinates, simplified as they arrive: Write
// LassoSelector::addPoint's live Ramer-Douglas-Peucker in chunks, from the
// second-to-last point of the previous simplification to the end.
class LassoPath {
 public:
  // `simplify`: the Ramer-Douglas-Peucker threshold in page units.
  void Add(Point p, double simplify);
  const std::vector<Point> &points() const { return points_; }

 private:
  std::vector<Point> points_;
  size_t simplify_start_ = 0;
};

// An element's bounds in page coordinates, as Write computes them: a
// stroke's centerline widened by half its size, a shape's geometry widened by
// half its stroke width, an image's box, or a group's children. A figure
// transforms its children's box as one element. Empty
// (left > right) for an empty group.
Rect ElementBounds(const Element &element);

Rect Union(const Rect &a, const Rect &b);
bool IsEmpty(const Rect &r);

// Write RectSelector::selectHit, RECTSEL_BBOX: the element's bounds lie
// inside `rect`.
bool InsideRect(const Element &element, const Rect &rect);

// Whether the lasso mesh (page coordinates) covers more than kLassoCoverage of
// every hit-test mesh of the element: a stroke's shape, a shape's strokes
// along its geometry, an image's or figure's box, each child of other groups.
bool LassoSelects(const ink::PartitionedMesh &lasso, const Element &element);

// Write RectSelector::shrink: the selection rectangle around the selected
// ink's bounds, padded so that it is at least 4 handle pads wide and high at
// view scale `scale` (view units per pt).
Rect SelectionRect(const Rect &bounds, double scale);

enum class HandleKind { kNone, kScale, kRotate, kMove };

struct HandleHit {
  HandleKind kind = HandleKind::kNone;
  Point origin;             // scale: the opposite corner; rotate: the center
  bool lock_ratio = false;  // the bottom-right corner scales proportionally
};

// Write ScribbleArea::selectionHit with RectSelector::scaleHandleHit and
// rotHandleHit: a corner handle, the rotate handle 6 handle sizes above the
// top edge's middle, or inside the rectangle. `touch` doubles the handle size.
HandleHit HitSelection(const Rect &rect, Point p, double scale, bool touch);

// The rotate handle's center.
Point RotateHandle(const Rect &rect, double scale);

// The element with `m` applied after its transform; ordinary groups transform
// their children, while a figure keeps one group transform.
Element Transformed(const Element &element, const Transform &m);

// Gives the element, and every element inside a group, a new id from `ids`.
Element WithNewIds(const Element &element, IdGenerator &ids);

// Gives each element whose id is in `taken` a new id. A pasted figure always
// gets a new id so its sidecars have independent file names.
Element WithFreeIds(const Element &element, const std::vector<std::string> &taken,
                    IdGenerator &ids);

// The ids of the elements, groups' children included.
void CollectIds(const Elements &elements, std::vector<std::string> &ids);

// Inline image files and both figure sidecars as base64 data: URLs (RFC 2397)
// so a clipboard document carries its assets to another notebook.
Element InlineImages(const Element &element, const std::string &page_file, const Assets &assets);

// Each image with a data: URL gets a file of the notebook. Figure sidecars
// always get independent files based on the figure id. New files are added to
// `assets` and `added`; hrefs become relative to `page_file`.
Element StoreImages(const Element &element, const std::string &page_file, Assets &assets,
                    NotebookFiles &added);

// The clipboard document: `elements` as a standalone page SVG
// (format/page_svg WritePage) whose one layer holds them at their page
// coordinates, sized to reach their bounds.
std::string ClipboardSvg(const Elements &elements, const std::string &layer_id);

// The elements of a clipboard document, every layer in order; none when
// `svg` does not parse as a page.
std::optional<Elements> ReadClipboard(std::string_view svg);

}  // namespace ink_engine
