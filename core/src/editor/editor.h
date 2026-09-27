// An editing session on one document: pen input to live and committed
// strokes, and the history of document values (docs/ARCHITECTURE.md: undo
// and redo move an index in a list of document values).
#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <string_view>
#include <vector>

#include "document/document.h"
#include "editor/erase.h"
#include "editor/history.h"
#include "ink.h"
#include "render/renderer.h"
#include "selection/selection.h"
#include "ink/brush/brush.h"
#include "ink/geometry/envelope.h"
#include "ink/strokes/in_progress_stroke.h"
#include "ink/strokes/input/stroke_input_batch.h"

namespace ink_engine {

struct Pen {
  InkBrush brush = INK_BRUSH_PRESSURE_PEN;
  Rgb color{26, 26, 26};
  float size = 1.6f;  // pt
  float opacity = 1;  // the stroke's fill-opacity
};

// "pressure-pen", "marker", "highlighter": the family names in mn:brush.
const char *BrushName(InkBrush brush);
// The brush of a family name; an unknown name is the pressure pen.
InkBrush BrushFromName(std::string_view name);

// The eraser radius in view units: Write ERASESTROKE_RADIUS and
// ERASEFREE_RADIUS (syncscribble/scribblearea.cpp:11-12, styluslabs/Write
// 401b65d), fixed on screen so that zooming changes how much is erased.
inline constexpr double kEraserRadius = 7;

// A view point in content coordinates, through the inverse of `view`.
Point ToContent(const Transform &view, double x, double y);

// google/ink stock brush for a pen, epsilon 0.01 pt.
ink::Brush MakeBrush(const Pen &pen);

// An element of a page: its layer and its index in that layer.
struct ElementRef {
  size_t layer = 0, index = 0;
  bool operator==(const ElementRef &) const = default;
};

// The selected elements of one page. They index into `value`; once the
// document's page is another value (an undo, another edit), the selection is
// gone, as Write clears it on every other edit.
struct Selection {
  size_t page = 0;
  immer::box<Page> value;
  std::vector<ElementRef> items;  // layer, then document order
  Rect rect;                      // Write RectSelector::selRect, page coordinates
};

class Editor {
 public:
  explicit Editor(DocumentHistory &history) : history_(&history) {}

  // content -> view affine transform, SVG matrix order. Content coordinates
  // are those of the page layout (layout/layout.h).
  void SetView(const Transform &content_to_view) { view_ = content_to_view; }
  void SetPen(const Pen &pen) { pen_ = pen; }
  // Added to host sample times (ms) to get UTC ms since the Unix epoch.
  void SetUtcOffset(double utc_minus_host_ms) { utc_offset_ms_ = utc_minus_host_ms; }
  // The eraser of the pen's eraser end and of the eraser tool; `active`: pen
  // and mouse input erase.
  void SetEraser(InkEraser kind, bool active) {
    eraser_kind_ = kind;
    eraser_active_ = active;
    if (active) selector_active_ = false;
  }
  // The selection tool; `active`: pen and mouse input select.
  void SetSelector(InkSelector kind, bool active) {
    selector_kind_ = kind;
    selector_active_ = active;
    if (active) eraser_active_ = false;
  }

  void Input(const InkPenSample *samples, size_t count);
  void InputUpdate(const InkPenSample *samples, size_t count);

  const Document &document() const { return history_->current(); }
  // The document as the canvas shows it: during an erase gesture, with the
  // erased strokes hidden or cut; while the selection is dragged, without it;
  // otherwise the document.
  const Document &Shown() const {
    return erase_ ? erase_->shown : transform_ ? transform_->shown : document();
  }

  // The selection; null when there is none or the document changed under it.
  const Selection *CurrentSelection();
  void ClearSelection();
  // Selects every element of the page's visible, unlocked layers.
  void SelectAll(size_t page);
  // Deletes the selection: one history step. False when nothing is selected.
  bool DeleteSelection();
  // The selection as a clipboard document (selection/selection.h
  // ClipboardSvg). A copy's elements get new ids; `cut` keeps the ids and
  // deletes the selection (Write scribbledoc.cpp:723-756, ID_COPYSEL and
  // ID_CUTSEL). Images carry their files from `assets` inline. Empty when
  // nothing is selected.
  std::string CopySelection(bool cut, const Assets &assets);
  // Adds the clipboard document's elements to the page under view point
  // (x, y), as the new selection: one history step. They keep their position
  // when it overlaps the view (`view_width` × `view_height` view units) and
  // their center and top left corner are on that page; otherwise they are
  // centered on (x, y), kept on the page. Inline images become files of
  // `assets`, the new ones also in `added`. False when `svg` does not parse.
  bool Paste(std::string_view svg, double x, double y, double view_width, double view_height,
             Assets &assets, NotebookFiles &added);
  // Copies the selection kDuplicateOffset right and down, new ids, as the
  // new selection: one history step. Figure sidecars become new assets.
  void DuplicateSelection(Assets &assets, NotebookFiles &added);
  enum class FigureCaptureError { kNone, kCrossPageInput, kPageChanged, kCrossLayerMove };
  // A capture owns pen strokes on one page and layer until completion.
  bool StartFigureCapture(size_t page, size_t layer);
  bool FigureCapturing() const { return figure_capture_.has_value(); }
  FigureCaptureError FigureCaptureStatus() const;
  void AcknowledgeFigureCaptureError();
  std::optional<std::vector<Stroke>> CapturedStrokes() const;
  // Groups the captured ink into one page element. Empty captures add nothing.
  // A live gesture or capture error leaves the session active.
  std::optional<Figure> CompleteFigureCapture();
  // Text uses the same page elements, history and selection transforms as ink.
  bool InsertText(std::string_view utf8, double x, double y);
  bool SelectTextAt(double x, double y);
  std::optional<std::string> SelectedText();
  bool SetSelectedText(std::string_view utf8);
  // What the canvas draws over the pages for the selection tools; none when
  // there is no selection and no lasso or rectangle is being drawn.
  std::optional<SelectionOverlay> Overlay();
  // Whether Overlay() changed since the last call.
  bool TakeOverlayChanged();
  const Transform &view() const { return view_; }

  // The stroke being drawn, if any: its page and pen, its outline in page
  // coordinates, and the page-space area its geometry changed in since the
  // last call.
  bool Drawing() const { return live_.has_value(); }
  size_t LivePage() const { return page_; }
  const Pen &LivePen() const { return live_->pen; }
  std::vector<Polyline> LiveOutline() const;
  ink::Envelope TakeUpdatedRegion();

 private:
  struct LiveStroke {
    ink::InProgressStroke stroke;
    InkTool tool;
    double t0 = 0;
    Pen pen;
    Point origin;                    // content position of the page
    std::vector<InkPenSample> real;  // page coordinates in x, y
    bool updated = false;            // ink_input_update changed a real sample
  };
  struct CommittedStroke {
    std::string id;
    size_t page = 0, layer = 0;
    double t0 = 0;
    Pen pen;
    Point origin;
    std::vector<InkPenSample> real;
  };
  struct FigureCapture {
    size_t page = 0, layer = 0, previous_layer = 0;
    std::string page_id, layer_id;
    std::set<std::string> stroke_ids;
    bool cross_page_input = false;
  };

  // A stroke or shape the free eraser touched: the strokes it is cut from (a
  // shape's strokes along its geometry) and the sections erased from each.
  struct FreeErased {
    std::vector<Stroke> strokes;
    std::vector<ErasedSections> erased;
    std::vector<Stroke> pieces;  // what remains of `strokes`, without ids
    bool stale = false;          // `erased` changed since `pieces`
  };
  // One eraser gesture on one page. Write's split: hit strokes are hidden
  // (tempSelection) and cut strokes replaced by their pieces
  // (freeErasePieces) until the release commits one history step
  // (syncscribble/scribblearea.cpp:1218-1254 freeErase, 1989-2017
  // doReleaseEvent, styluslabs/Write 401b65d).
  struct EraseGesture {
    InkEraser kind = INK_ERASER_STROKE;
    InkTool tool = INK_TOOL_PEN;
    size_t page = 0;
    Point origin;       // content position of the page
    Point last;         // page coordinates
    double radius = 0;  // pt
    std::string time;   // gesture start, for shapes turned into strokes
    std::set<std::string> hit;                    // stroke eraser: ids
    std::map<std::string, FreeErased> free;       // free eraser: by element id
    std::map<std::string, std::vector<ink::Stroke>> meshes;  // hit-test strokes by id
    Document shown;
  };

  // A lasso or rectangle being drawn (Write MODE_SELECTLASSO, MODE_SELECTRECT;
  // scribblearea.cpp:1560-1567, 1716-1731, 2019-2037).
  struct SelectGesture {
    InkSelector kind = INK_SELECTOR_LASSO;
    InkTool tool = INK_TOOL_PEN;
    size_t page = 0;
    Point origin;       // content position of the page
    Point start, last;  // page coordinates
    LassoPath lasso;
  };
  // A drag of the selection or of one of its handles (Write MODE_MOVESELFREE,
  // MODE_SCALESEL, MODE_ROTATESEL; scribblearea.cpp:1735-1832, 2045-2139).
  struct TransformGesture {
    HandleHit hit;
    InkTool tool = INK_TOOL_PEN;
    Point origin;   // content position of the selection's page
    Point initial;  // page coordinates of the pen-down
    Transform live;  // page coordinates, applied after the elements' transforms
    Document shown;  // the document without the selection, which floats
  };
  // What a pen-down starts.
  enum class Route { kDraw, kErase, kSelect, kTransform, kIgnore };

  Route Begin(const InkPenSample &sample);
  double ViewScale() const;
  void SelectInput(const InkPenSample *samples, size_t count);
  void FinishSelect();
  void TransformInput(const InkPenSample *samples, size_t count);
  void UpdateTransform(Point at);
  void CommitTransform(Point content);
  void IgnoreInput(const InkPenSample *samples, size_t count);
  // Pushes `next`, whose page `page` holds `items`, and selects them.
  void PushSelection(Document next, size_t page, std::vector<ElementRef> items);
  Elements Selected(const Selection &selection) const;
  bool Erases(const InkPenSample &sample) const;
  void EraseInput(const InkPenSample *samples, size_t count);
  void EraseAlong(Point from, Point to);
  const std::vector<ink::Stroke> &HitStrokes(const std::string &id, const Element &element);
  void UpdateShown();
  void CommitErase();
  // The gesture's page with hit elements removed and cut ones replaced by
  // their pieces; with `ids`, each piece gets a new id.
  Page ErasedPage(IdGenerator *ids) const;

  ink::StrokeInput ToStrokeInput(const InkPenSample &sample, double t0) const;
  ink::StrokeInputBatch Batch(const std::vector<InkPenSample> &samples, double t0) const;
  InkPenSample ToPage(InkPenSample sample, const Point &origin) const;
  void Commit();
  Stroke MakeElement(const std::string &id, const ink::Stroke &ink_stroke, const Pen &pen,
                     double t0, const std::vector<InkPenSample> &real) const;

  DocumentHistory *history_;
  Transform view_;
  Pen pen_;
  double utc_offset_ms_ = 0;
  size_t page_ = 0, layer_ = 0;
  InkEraser eraser_kind_ = INK_ERASER_STROKE;
  bool eraser_active_ = false;
  InkSelector selector_kind_ = INK_SELECTOR_LASSO;
  bool selector_active_ = false;
  std::optional<LiveStroke> live_;
  std::optional<EraseGesture> erase_;
  std::optional<SelectGesture> select_;
  std::optional<TransformGesture> transform_;
  // A pen-down that only cleared the selection; its gesture draws nothing
  // (Write's clearSelOnly, scribblearea.cpp:1428-1431).
  std::optional<InkTool> ignored_;
  std::optional<Selection> selection_;
  uint64_t overlay_version_ = 0, overlay_taken_ = 0;
  std::vector<CommittedStroke> committed_;
  std::optional<FigureCapture> figure_capture_;
};

}  // namespace ink_engine
