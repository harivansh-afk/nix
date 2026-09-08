# Laptop workspaces and Desk

Option–1 through Option–9 select numbered workspaces on the built-in display.
Desk is a separate workspace on the first external display matched by AeroSpace,
regardless of which display macOS calls primary. Its name never changes as laptop
workspaces fill up.

| Shortcut | Action |
| --- | --- |
| Option–D | Focus Desk |
| Option–Shift–D | Move the focused window to Desk and follow it |
| Option–1…9 | Focus a numbered laptop workspace |
| Option–Shift–1…9 | Move the focused window to that numbered workspace |
| Option–period | Focus the next monitor |
| Option–Shift–period | Move the window to the next monitor and follow it |

New windows use AeroSpace's normal placement rather than app-specific numbered
destinations. Desk stays visible in the bar even when empty. Moving an entire
workspace between monitors is no longer bound: forced assignments fix their homes.

With only the laptop connected, Desk falls back to the built-in display. With
only an external display connected (clamshell), all workspaces remain accessible
there. With both connected, numbered workspaces return to the laptop and Desk
belongs to the external display. This configuration targets one external display;
multiple external displays would need explicit named assignments.

## Activate after merging

From the main checkout:

```sh
git pull --ff-only origin main
just switch
aerospace reload-config
sketchybar --reload
```

The rebuild installs the updated bar feed. The reloads pick up the live dotfiles.

Existing windows on the old external workspace (such as 10) are not automatically
migrated. Focus each window and press Option–Shift–D to move it to Desk. The old
workspace can disappear once it is empty and no longer visible.

## Check the result

1. Press Option–D, then Option–Shift–D with a window focused. Desk should be on
   the external display and its bar tab should highlight.
2. Use Option–1, Option–6 and Option–9. They should switch only the laptop's
   workspace, leaving Desk visible externally.
3. Open a new browser window on Desk; confirm it stays there.
4. Disconnect the display. Option–D must still reach its windows on the laptop.
5. Reconnect. Check that Desk returns externally and numbered workspaces remain
   on the laptop. Also check clamshell mode if used.

Inspect assignments with:

```sh
aerospace list-workspaces --all --format '%{workspace} | %{monitor-name}'
```

Physical display reconnection and live shortcut acceptance are post-activation
checks; static validation does not establish those results.
