"""Locate an enabled native Chrome button through Linux AT-SPI."""

import json
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi


def locate(node, name):
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


print(json.dumps(locate(Atspi.get_desktop(0), sys.argv[1])))
