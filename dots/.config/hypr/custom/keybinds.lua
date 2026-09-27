-- Custom keybinds.
--
-- Sourced from hyprland.lua AFTER hyprland/keybinds.lua, so anything bound
-- here replaces a default only if you unbind it first. The file is only read
-- if it exists.
--
-- This copy in the repo is an EMPTY TEMPLATE apart from the self-service
-- helper below. The installer copies it only when ~/.config/hypr/custom/ does
-- not already exist (mode: skip-if-exists in
-- sdata/subcmd-install/3.files-exp.yaml), so your own binds are never
-- overwritten by a re-run.
--
-- To take over a default, unbind it and then bind your own:
--   hl.unbind("SUPER + Q")
--   hl.bind("SUPER + Q", hl.dsp.exec_cmd("firefox"))
--
-- Other dispatchers:
--   hl.dsp.exec_cmd("kitty")                 run a command
--   hl.dsp.global("quickshell:settingsToggle")  quickshell IPC
--   hl.dsp.window.close()                    window control
--   hl.dsp.exec()                            raw hyprland dispatch

-- Open this file in your editor. Kept active in the template on purpose, so a
-- fresh install has a way to reach this file without hunting for it.
hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

-- Example: replace the default browser launcher.
-- hl.unbind("SUPER + W")
-- hl.bind("SUPER + W", hl.dsp.exec_cmd("firefox"), { description = "App: Browser" })

-- Example: launch a terminal.
-- hl.unbind("SUPER + B")
-- hl.bind("SUPER + B", hl.dsp.exec_cmd("kitty -e btop"), { description = "App: btop" })

-- Example: toggle the shell settings.
-- hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
