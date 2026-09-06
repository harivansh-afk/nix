import argparse
import json
from pathlib import Path

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

parser = argparse.ArgumentParser()
parser.add_argument("--state", required=True, type=Path)
args = parser.parse_args()
state = {"name": "", "applications": 0, "output": "No application yet."}


def save_state():
    temporary = args.state.with_name(args.state.name + ".tmp")
    temporary.write_text(json.dumps(state) + "\n")
    temporary.replace(args.state)


window = Gtk.Window(title="Spark Computer Acceptance")
window.set_default_size(480, 220)
window.set_border_width(24)
window.connect("destroy", Gtk.main_quit)
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
window.add(box)
entry = Gtk.Entry()
entry.get_accessible().set_name("Name")
label = Gtk.Label.new_with_mnemonic("_Name")
label.set_mnemonic_widget(entry)
label.set_xalign(0)
button = Gtk.Button.new_with_mnemonic("_Apply")
output = Gtk.Label(label=state["output"])
output.set_xalign(0)


def apply(_widget):
    state["name"] = entry.get_text()
    state["applications"] += 1
    state["output"] = f"Applied: {state['name']}; Count: {state['applications']}"
    output.set_text(state["output"])
    save_state()


button.connect("clicked", apply)
entry.connect("activate", apply)
for widget in (label, entry, button, output):
    box.pack_start(widget, False, False, 0)
save_state()
window.show_all()
entry.grab_focus()
Gtk.main()
