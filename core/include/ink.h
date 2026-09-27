/* Ink engine C ABI v1. Swift and TypeScript see only this header: opaque
   handles and plain structs with fixed layouts (docs/ARCHITECTURE.md).

   Every call returns an InkStatus. On an error, ink_last_error() gives the
   message. No C++ exception crosses the ABI. */
#ifndef INK_H
#define INK_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum InkStatus {
  INK_OK = 0,
  INK_ERROR_ARGUMENT = 1, /* a null handle or pointer, or a bad value */
  INK_ERROR_PARSE = 2,    /* a notebook or page file that does not parse */
  INK_ERROR_GPU = 3,      /* no GPU context or surface */
  INK_ERROR_INTERNAL = 4  /* an engine failure */
} InkStatus;

/* Engine version string, "MAJOR.MINOR.PATCH". Static storage. */
const char *ink_version(void);

/* The message of the last call that did not return INK_OK. Valid until the
   next failing call. */
const char *ink_last_error(void);

/* ---- Documents -------------------------------------------------------- */

typedef struct InkDocument InkDocument;

typedef enum InkFileKind {
  INK_FILE_WRITE = 0, /* write `bytes` to `path` */
  INK_FILE_DELETE = 1 /* delete `path` (a deleted page); `bytes` is null */
} InkFileKind;

/* One file of a notebook directory. `path` is relative to the notebook,
   e.g. "pages/0001.svg". */
typedef struct InkFile {
  const char *path;
  const uint8_t *bytes;
  size_t size;
  uint32_t kind; /* InkFileKind */
} InkFile;

/* A new notebook with one blank A4 page and one layer. `seed` seeds the id
   generator. */
InkStatus ink_document_create(uint64_t seed, InkDocument **out);
typedef enum InkPageSize { INK_PAGE_A4 = 0, INK_PAGE_LETTER = 1, INK_PAGE_CUSTOM = 2 } InkPageSize;
/* A new notebook as ink_document_create, with template `name` set as by
   ink_document_set_template and page 1 on that template's background. The
   selected page size sets both the first page and future pages. The document
   starts with no undo step. */
InkStatus ink_document_create_from_template(uint64_t seed, const char *name, const uint8_t *svg,
                                            size_t size, InkPageSize page_size, double width,
                                            double height, InkDocument **out);
/* Replaces the document with the notebook of notebook.json. Its listed pages
   are error pages ("missing file") until ink_document_load_page loads them. */
InkStatus ink_document_load_notebook(InkDocument *document, const uint8_t *json, size_t size);
/* Loads one page file. A file that does not parse returns INK_ERROR_PARSE and
   stays in the document as an error page, which is shown and never written. */
InkStatus ink_document_load_page(InkDocument *document, const char *file, const uint8_t *svg,
                                 size_t size);
/* An image file the pages reference, e.g. "assets/p0017.png". */
InkStatus ink_document_load_asset(InkDocument *document, const char *path, const uint8_t *bytes,
                                  size_t size);
/* Reads an asset already loaded or created by this document. */
InkStatus ink_document_asset(InkDocument *document, const char *path,
                             const uint8_t **bytes, size_t *size);
/* The files that changed since the last save. `*files` stays valid until the
   next call on the document. */
InkStatus ink_document_dirty_files(InkDocument *document, const InkFile **files, size_t *count);
/* The host wrote the dirty files. */
InkStatus ink_document_mark_saved(InkDocument *document);
/* The laid-out pages' extent in content coordinates (pt), for
   ink_canvas_set_view. */
InkStatus ink_document_content_size(InkDocument *document, double *width, double *height);
/* Frees the document. Free its canvases first. */
InkStatus ink_document_free(InkDocument *document);

/* ---- Pages and templates ---------------------------------------------- */

/* Listed pages, in notebook.json order. Page indices below count these. */
InkStatus ink_document_page_count(InkDocument *document, size_t *count);
/* A new page before page `index` (the count appends), in the notebook's page
   size, with the template's background. One history step each. */
InkStatus ink_document_insert_page(InkDocument *document, size_t index);
/* Removes a page; ink_document_dirty_files then lists its file for deletion. */
InkStatus ink_document_delete_page(InkDocument *document, size_t index);
/* Moves page `from` to position `to`. Page files keep their names. */
InkStatus ink_document_move_page(InkDocument *document, size_t from, size_t to);

/* The size of new pages: A4, Letter, or `width` × `height` pt. */
InkStatus ink_document_set_page_size(InkDocument *document, InkPageSize size, double width,
                                     double height);

/* The notebook's template: `name` under Notes/.templates/, and the bytes of
   that template notebook's pages/0001.svg, whose background new pages copy. */
InkStatus ink_document_set_template(InkDocument *document, const char *name, const uint8_t *svg,
                                    size_t size);
/* The built-in templates the host writes to Notes/.templates/ on first use. */
InkStatus ink_builtin_template_count(size_t *count);
InkStatus ink_builtin_template_name(size_t index, const char **name);
/* A document of the built-in template `name`, never saved: its dirty files
   are the template notebook's files. */
InkStatus ink_builtin_template_create(const char *name, uint64_t seed, InkDocument **out);

/* ---- Input ------------------------------------------------------------ */

typedef enum InkTool { INK_TOOL_PEN = 0, INK_TOOL_ERASER = 1, INK_TOOL_TOUCH = 2, INK_TOOL_MOUSE = 3 } InkTool;

typedef enum InkPhase {
  INK_PHASE_HOVER = 0,
  INK_PHASE_BEGIN = 1,
  INK_PHASE_MOVE = 2,
  INK_PHASE_END = 3,
  INK_PHASE_CANCEL = 4
} InkPhase;

/* Capability bits: set when the platform measures the value. */
enum {
  INK_HAS_PRESSURE = 1u << 0,
  INK_HAS_ALTITUDE = 1u << 1,
  INK_HAS_AZIMUTH = 1u << 2,
  INK_HAS_ROLL = 1u << 3,
  INK_HAS_HOVER_HEIGHT = 1u << 4
};

typedef struct InkPenSample {
  double x, y;        /* view coordinates: CSS px, UIKit points */
  double time;        /* ms, monotonic clock of the host */
  float pressure;     /* 0..1 */
  float altitude;     /* rad, 0 = parallel to the screen */
  float azimuth;      /* rad */
  float roll;         /* rad: Pencil Pro rollAngle, web twist */
  float hover_height; /* 0..1, UIKit zOffset; iPad only */
  uint32_t buttons;   /* web buttons bits; 32 = eraser */
  uint32_t has;       /* INK_HAS_* capability bits */
  uint32_t id;        /* host sample id, for later updates */
  uint8_t tool;       /* InkTool */
  uint8_t phase;      /* InkPhase */
  uint8_t predicted;  /* 1 for a predicted sample */
  uint8_t reserved;
} InkPenSample;

/* ---- Canvases --------------------------------------------------------- */

typedef struct InkCanvas InkCanvas;

typedef enum InkBrush {
  INK_BRUSH_PRESSURE_PEN = 0,
  INK_BRUSH_MARKER = 1,
  INK_BRUSH_HIGHLIGHTER = 2
} InkBrush;

/* The tool that new pen input uses. A stroke keeps the brush, color, opacity
   and size it was drawn with. */
typedef struct InkToolSettings {
  uint32_t brush; /* InkBrush */
  uint32_t rgb;   /* 0xRRGGBB */
  float size;     /* pt */
  float opacity;  /* (0, 1]: the stroke's fill-opacity */
} InkToolSettings;

/* ---- Pen presets ------------------------------------------------------ */

/* One preset of Notes/.pens.json (docs/FORMAT.md, Other files). */
typedef struct InkPen {
  const char *id;
  const char *name;
  InkToolSettings tool;
} InkPen;

/* The bytes of the default .pens.json, which the host writes on first use.
   `*json` stays valid until the next ink_pens_* call. */
InkStatus ink_pens_default(const uint8_t **json, size_t *size);
/* The presets of a .pens.json, in toolbar order. `*pens` and its strings stay
   valid until the next ink_pens_* call. INK_ERROR_PARSE when the file is not
   a pen list. */
InkStatus ink_pens_read(const uint8_t *json, size_t size, const InkPen **pens, size_t *count);
/* The .pens.json of `pens`. `*json` stays valid until the next ink_pens_*
   call. */
InkStatus ink_pens_write(const InkPen *pens, size_t count, const uint8_t **json, size_t *size);

#ifdef __EMSCRIPTEN__
/* A canvas on `document` that draws into the WebGL2 canvas element matched
   by the CSS `selector`. */
InkStatus ink_canvas_create_webgl(InkDocument *document, const char *selector, InkCanvas **out);
#endif
#ifdef __APPLE__
/* A canvas on `document` that draws into `layer`, a CAMetalLayer, with the
   host's MTLDevice and MTLCommandQueue. All three are passed unretained and
   must outlive the canvas. */
InkStatus ink_canvas_create_metal(InkDocument *document, void *device, void *queue, void *layer,
                                  InkCanvas **out);
#endif
/* The content -> view transform, as SVG matrix(a, b, c, d, e, f). Content
   coordinates are pt: the listed pages stacked top to bottom with a 9.6 pt
   gap, each centered on the widest. */
InkStatus ink_canvas_set_view(InkCanvas *canvas, double a, double b, double c, double d, double e,
                              double f);
/* The surface size in device pixels, and device pixels per view unit (CSS
   devicePixelRatio, UIKit contentScaleFactor). */
InkStatus ink_canvas_set_surface_size(InkCanvas *canvas, int32_t width, int32_t height,
                                      float pixel_ratio);
InkStatus ink_canvas_set_tool(InkCanvas *canvas, const InkToolSettings *tool);
/* Captures pen strokes on one page and layer as one editable TikZ figure.
   The scene is FreeTikZ scene JSON with the original ink samples. The host
   generates TikZ from that scene before completion. Returned bytes remain
   valid until the next figure call on this canvas. An empty capture returns
   an empty figure id. */
InkStatus ink_canvas_figure_begin(InkCanvas *canvas, size_t page, size_t layer);
InkStatus ink_canvas_figure_scene(InkCanvas *canvas, const uint8_t **json, size_t *size);
InkStatus ink_canvas_figure_complete(InkCanvas *canvas, const uint8_t *scene, size_t scene_size,
                                     const uint8_t *tikz, size_t tikz_size,
                                     const uint8_t **figure_id, size_t *id_size);
/* ID of the one selected figure; empty when selection is not one figure. */
InkStatus ink_canvas_selected_figure(InkCanvas *canvas, const uint8_t **id, size_t *size);
typedef enum InkEraser {
  INK_ERASER_STROKE = 0, /* deletes each stroke or shape it touches */
  INK_ERASER_FREE = 1    /* removes only the touched parts, splitting strokes */
} InkEraser;

/* The eraser that pen eraser input (INK_TOOL_ERASER, or `buttons` bit 32)
   uses. With `active` 1 the eraser tool is selected: pen and mouse input
   erase too. The radius is 7 view units. One gesture is one history step. */
InkStatus ink_canvas_set_eraser(InkCanvas *canvas, InkEraser kind, int32_t active);

typedef enum InkSelector {
  INK_SELECTOR_LASSO = 0, /* selects what a drawn loop covers */
  INK_SELECTOR_RECT = 1   /* selects what lies inside a dragged rectangle */
} InkSelector;

/* The selection tool. With `active` 1, pen and mouse input select, and
   setting it turns the eraser tool off (as setting the eraser active turns
   this off). Whatever the tool, a pen-down on the selection moves it, on a
   corner handle scales it (the bottom-right corner keeping the aspect
   ratio), and on the handle above it rotates it: one history step each. A
   pen-down elsewhere clears the selection; with the pen tool it draws
   nothing. */
InkStatus ink_canvas_set_selector(InkCanvas *canvas, InkSelector kind, int32_t active);

typedef struct InkSelectionInfo {
  uint32_t count;       /* selected elements; 0: no selection */
  int32_t page;         /* the selection's page, or -1 */
  double x, y;          /* the selection rectangle in view coordinates */
  double width, height;
} InkSelectionInfo;

InkStatus ink_canvas_selection(InkCanvas *canvas, InkSelectionInfo *out);
/* Selects every element of page `index`'s visible, unlocked layers. */
InkStatus ink_canvas_select_all(InkCanvas *canvas, size_t index);
InkStatus ink_canvas_clear_selection(InkCanvas *canvas);
/* Deletes the selected elements: one history step. */
InkStatus ink_canvas_delete_selection(InkCanvas *canvas);
/* The selection as a standalone SVG document (UTF-8), for the host's
   clipboard. A copy's elements get new ids; with `cut` 1 they keep their ids
   and the selection is deleted (one history step). `*svg` stays valid until
   the next call on the canvas; `*size` is 0 when nothing is selected. */
InkStatus ink_canvas_copy_selection(InkCanvas *canvas, int32_t cut, const uint8_t **svg,
                                    size_t *size);
/* Adds the elements of a clipboard document to the page under view point
   (x, y) and selects them: one history step. They keep their position when
   it overlaps the surface (ink_canvas_set_surface_size) and their center and
   top left corner are on that page, and are centered on (x, y) otherwise.
   An element whose id is already on the page gets a new id. An image copied
   from another notebook carries its file inline; paste adds it to this
   notebook's assets (reusing a file with the same bytes), and
   ink_document_dirty_files lists the new file. INK_ERROR_PARSE when `svg` is
   not a page SVG. */
InkStatus ink_canvas_paste(InkCanvas *canvas, const uint8_t *svg, size_t size, double x,
                           double y);
/* Copies the selection 10 pt right and down, with new ids, and selects the
   copy: one history step. */
InkStatus ink_canvas_duplicate_selection(InkCanvas *canvas);
/* Adds UTF-8 text at a view point and selects it. Each line is SVG text in
   the page file. The position is the text box's top-left corner. */
InkStatus ink_canvas_insert_text(InkCanvas *canvas, const uint8_t *utf8, size_t size,
                                 double x, double y);
/* Selects the topmost text box at a view point; `found` is 0 when none. */
InkStatus ink_canvas_select_text_at(InkCanvas *canvas, double x, double y, int32_t *found);
/* The selected text box as UTF-8, with newline-separated lines. The buffer
   stays valid until the next call on the canvas. `size` is 0 when no text box
   is selected. */
InkStatus ink_canvas_selected_text(InkCanvas *canvas, const uint8_t **utf8, size_t *size);
/* Replaces the selected text box's content in one history step. */
InkStatus ink_canvas_set_selected_text(InkCanvas *canvas, const uint8_t *utf8, size_t size);
/* UTC ms since the Unix epoch minus the host's sample clock, for mn:time. */
InkStatus ink_canvas_set_utc_offset(InkCanvas *canvas, double utc_minus_host_ms);
InkStatus ink_canvas_free(InkCanvas *canvas);
/* The page under view point (x, y): its index, or -1 for none. */
InkStatus ink_canvas_page_at(InkCanvas *canvas, double x, double y, int32_t *page);

/* One batch of samples per platform event. */
InkStatus ink_input(InkCanvas *canvas, const InkPenSample *samples, size_t count);
/* Replaces the values of earlier samples with the same `id` (UIKit estimated
   properties arrive late, sometimes after the touch ends). */
InkStatus ink_input_update(InkCanvas *canvas, const InkPenSample *samples, size_t count);

/* ---- Frame and history ------------------------------------------------ */

/* Draws a frame when the document, the view, or the live stroke changed
   since the last one. `*drew` is 1 when it drew. */
InkStatus ink_render(InkCanvas *canvas, int32_t *drew);
/* Moves the document one step back or forward in its history. `*moved` is 0
   at either end. `*page` is the page the step changed, for the host to show,
   or -1 when it changed no page (a page size or template). */
InkStatus ink_undo(InkDocument *document, int32_t *moved, int32_t *page);
InkStatus ink_redo(InkDocument *document, int32_t *moved, int32_t *page);
/* A listed page's rectangle in content coordinates (pt). */
InkStatus ink_document_page_rect(InkDocument *document, size_t index, double *x, double *y,
                                 double *width, double *height);
/* A PNG of listed page `index`, `width` pixels wide, its height in the page's
   proportion: the library's thumbnail. Needs no canvas. `*png` stays valid
   until the next call of this function on the document. */
InkStatus ink_document_page_png(InkDocument *document, size_t index, int32_t width,
                                const uint8_t **png, size_t *size);

/* A zero-based consecutive page range. `include_links` is reserved for link
   annotations (#32) and must be zero. Hidden layers are omitted unless
   `include_hidden_layers` is nonzero. */
typedef struct InkPdfExportSpec {
  size_t first_page;
  size_t page_count;
  uint32_t include_links;
  uint32_t include_hidden_layers;
} InkPdfExportSpec;

/* Exports the range as PDF at each page's native point size. `title` is the
   UTF-8 note title supplied by the host. The bytes stay valid until the next
   export on this document or ink_document_free. */
InkStatus ink_export_pdf(InkDocument *document, const char *title,
                         const InkPdfExportSpec *spec, const uint8_t **pdf, size_t *size);

/* ---- Layout check ----------------------------------------------------- */

typedef enum InkStruct {
  INK_STRUCT_PEN_SAMPLE = 0,
  INK_STRUCT_TOOL_SETTINGS = 1,
  INK_STRUCT_FILE = 2,
  INK_STRUCT_SELECTION_INFO = 3,
  INK_STRUCT_PEN = 4,
  INK_STRUCT_PDF_EXPORT_SPEC = 5
} InkStruct;

/* The struct's size, then the offset of each field in declaration order,
   into `out`. `*count` is the number of values. Wrappers in other languages
   compare their layouts with these. */
InkStatus ink_struct_layout(InkStruct which, uint32_t *out, size_t capacity, size_t *count);

#ifdef __cplusplus
}

static_assert(offsetof(InkPenSample, x) == 0);
static_assert(offsetof(InkPenSample, y) == 8);
static_assert(offsetof(InkPenSample, time) == 16);
static_assert(offsetof(InkPenSample, pressure) == 24);
static_assert(offsetof(InkPenSample, altitude) == 28);
static_assert(offsetof(InkPenSample, azimuth) == 32);
static_assert(offsetof(InkPenSample, roll) == 36);
static_assert(offsetof(InkPenSample, hover_height) == 40);
static_assert(offsetof(InkPenSample, buttons) == 44);
static_assert(offsetof(InkPenSample, has) == 48);
static_assert(offsetof(InkPenSample, id) == 52);
static_assert(offsetof(InkPenSample, tool) == 56);
static_assert(offsetof(InkPenSample, phase) == 57);
static_assert(offsetof(InkPenSample, predicted) == 58);
static_assert(offsetof(InkPenSample, reserved) == 59);
static_assert(sizeof(InkPenSample) == 64);

static_assert(offsetof(InkToolSettings, brush) == 0);
static_assert(offsetof(InkToolSettings, rgb) == 4);
static_assert(offsetof(InkToolSettings, size) == 8);
static_assert(offsetof(InkToolSettings, opacity) == 12);
static_assert(sizeof(InkToolSettings) == 16);

/* Pointer-sized fields: 4 bytes on wasm32, 8 on arm64. */
static_assert(offsetof(InkFile, path) == 0);
static_assert(offsetof(InkFile, bytes) == sizeof(void *));
static_assert(offsetof(InkFile, size) == 2 * sizeof(void *));
static_assert(offsetof(InkFile, kind) == 3 * sizeof(void *));
static_assert(sizeof(InkFile) == 4 * sizeof(void *));

static_assert(offsetof(InkPen, id) == 0);
static_assert(offsetof(InkPen, name) == sizeof(void *));
static_assert(offsetof(InkPen, tool) == 2 * sizeof(void *));
static_assert(sizeof(InkPen) == 2 * sizeof(void *) + sizeof(InkToolSettings));

static_assert(offsetof(InkSelectionInfo, count) == 0);
static_assert(offsetof(InkSelectionInfo, page) == 4);
static_assert(offsetof(InkSelectionInfo, x) == 8);
static_assert(offsetof(InkSelectionInfo, y) == 16);
static_assert(offsetof(InkSelectionInfo, width) == 24);
static_assert(offsetof(InkSelectionInfo, height) == 32);
static_assert(sizeof(InkSelectionInfo) == 40);

static_assert(offsetof(InkPdfExportSpec, first_page) == 0);
static_assert(offsetof(InkPdfExportSpec, page_count) == sizeof(size_t));
static_assert(offsetof(InkPdfExportSpec, include_links) == 2 * sizeof(size_t));
static_assert(offsetof(InkPdfExportSpec, include_hidden_layers) == 2 * sizeof(size_t) + 4);
static_assert(sizeof(InkPdfExportSpec) == 2 * sizeof(size_t) + 8);
#endif

#endif
