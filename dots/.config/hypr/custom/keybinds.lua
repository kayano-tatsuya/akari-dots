hl.bind("CTRL+SUPER+ALT+Slash", hl.dsp.exec_cmd("xdg-open ~/.config/hypr/custom/keybinds.lua"), {description = "Edit user keybinds"} )

hl.unbind("SUPER + W")
hl.bind("SUPER + W", hl.dsp.exec_cmd("/home/kayano-tatsuya/.local/opt/floorp/floorp"), { description = "App: Browser" })

hl.unbind("SUPER + B")
hl.bind("SUPER + B", hl.dsp.exec_cmd("kitty -e btop"), { description = "App: btop" })

hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
