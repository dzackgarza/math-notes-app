"""Locate an enabled native Chrome button through Linux AT-SPI."""

import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


def locate(node, name):
    # A native dialog can disappear between reading its child count and
    # obtaining a child. AT-SPI returns no accessible for the removed node.
    if node is None:
        return None
    if name == "--focused-entry" and node.get_role_name() in ("text", "entry"):
        if node.get_state_set().contains(Atspi.StateType.FOCUSED):
            text = Atspi.Text.get_text(node, 0, -1)
            selection = None
            if Atspi.Text.get_n_selections(node):
                selected = Atspi.Text.get_selection(node, 0)
                selection = [selected.start_offset, selected.end_offset]
            return {"text": text, "selection": selection}
    if node.get_role_name() == "push button" and node.get_name() == name:
        states = node.get_state_set()
        if states.contains(Atspi.StateType.SENSITIVE):
            rect = node.get_extents(Atspi.CoordType.SCREEN)
            if rect.width > 0 and rect.height > 0:
                return [rect.x + rect.width // 2, rect.y + rect.height // 2]
    for index in range(node.get_child_count()):
        found = locate(node.get_child_at_index(index), name)
        if found is not None:
            return found
    return None


desktop = Atspi.get_desktop(0)
if len(sys.argv) > 2:
    # The observed native chooser window identifies its owning application.
    # Do not traverse the entire Flutter document to find a GTK entry.
    owner = int(sys.argv[2])
    result = None
    for index in range(desktop.get_child_count()):
        app = desktop.get_child_at_index(index)
        if app is not None and app.get_process_id() == owner:
            # GTK owns its tree search. One Collection query avoids a D-Bus
            # round trip for every row in a populated native file chooser.
            rule = Atspi.MatchRule.new(
                Atspi.StateSet.new([Atspi.StateType.FOCUSED]),
                Atspi.CollectionMatchType.ALL,
                {}, Atspi.CollectionMatchType.EMPTY,
                [Atspi.Role.ENTRY, Atspi.Role.TEXT], Atspi.CollectionMatchType.ANY,
                [], Atspi.CollectionMatchType.EMPTY, False,
            )
            matches = Atspi.Collection.get_matches(
                app, rule, Atspi.CollectionSortOrder.CANONICAL, 1, True
            )
            result = locate(matches[0], sys.argv[1]) if matches else None
            break
else:
    result = locate(desktop, sys.argv[1])
print(json.dumps(result))
