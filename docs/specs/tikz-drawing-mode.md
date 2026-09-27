# TikZ drawing mode

## Result

Drawing mode associates a notebook sketch with an interpreted diagram and
editable TikZ source. Selecting the diagram exposes its source for copying
into a separate typeset document. The notebook retains the drawing.

## User workflow

1. Enter Drawing mode and draw a diagram.
2. Complete the drawing and inspect its interpretation.
3. Correct the interpretation or edit its TikZ source.
4. Select the diagram and copy its TikZ source.
5. Save and reopen the note with the drawing and source still associated.

Interpretation should express diagram structure in TikZ. Retaining input
samples or emitting a coordinate trace alone does not complete the feature.
Preserve original ink so an interpretation can be revised.

## Component ownership

The existing FreeTikZ capture integration owns the captured figure and
original ink. TikZ Editor provides the source editor, supported visual
interpretation, and source edits. The notebook adapter owns figure identity,
persistence, selection, and clipboard delivery.

The next implementation step is to connect captured diagram interpretation
to editable source and a clear Copy TikZ action. Use existing dependency
capabilities for the supported diagram vocabulary.

## Acceptance

A drawn diagram can be interpreted, corrected, saved, reopened, selected,
and copied as usable TikZ code. Paste that code into a separate typeset
document to demonstrate the intended output. Notebook export preserves the
visible note drawing.

Issue #10 owns this workflow. The web daily-use milestone includes this
workflow alongside ordinary note editing and saving.
