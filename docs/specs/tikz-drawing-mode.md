# TikZ drawing mode

## Result

Drawing mode extracts a TikZ skeleton from the geometric structure of a
doodle. The code seeds a figure in an external paper-writing workflow or
TikZ editor. The notebook preserves the handwritten draft.

## Permanent boundary

- Notebook pages are never required to export as LaTeX or render through TeX.
- Written text, symbols, formulas, and diagram labels remain ink. This feature
  does not recognize or transcribe handwriting.
- The app does not add LaTeX labels, project preambles, or a paper-typesetting
  workflow. Labels and publication refinement belong to the external editor.
- A useful geometric skeleton is the output. Publication-ready source,
  typeset previews, and matching a paper's rendered appearance are not
  acceptance requirements.

These exclusions define the product, including after v1. They are not a
backlog of deferred features. A dependency's additional features do not
create application requirements.

## User workflow

1. Enter Drawing mode and draw a diagram.
2. Complete the drawing and inspect the extracted diagram structure.
3. Select the diagram and copy its TikZ skeleton.
4. Refine the figure and add typeset labels in an external authoring tool.
5. Save and reopen the note with the original drawing and source associated.

Interpretation should express diagram structure in TikZ. Retaining input
samples or emitting a coordinate trace alone does not complete the feature.
Preserve original ink so an interpretation can be revised.

## Component ownership

The existing FreeTikZ capture integration owns the captured figure and
original ink. TikZ Editor provides supported geometric and source operations.
The notebook adapter owns figure identity,
persistence, selection, and clipboard delivery.

The next implementation step is to connect captured diagram interpretation
to editable source and a clear Copy TikZ action. Use existing dependency
capabilities for the supported diagram vocabulary.

## Acceptance

A doodle yields a reusable TikZ skeleton that can be selected and copied
into an external figure-editing workflow. Save and reopen preserve its
association with the original drawing. Handwritten labels remain unchanged.
Notebook export preserves the visible note drawing.

Issue #10 owns this workflow. The web daily-use milestone includes this
workflow alongside ordinary note editing and saving.
