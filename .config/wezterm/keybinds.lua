-- reference: https://github.com/aperum/dotfiles/blob/main/.config/wezterm/keys.lua

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

function M.apply_to_config(config)
    config.keys = {
        { key = 't', mods = 'CTRL', action = act.SpawnTab('CurrentPaneDomain') },
        { key = 'w', mods = 'CTRL', action = act.CloseCurrentTab{ confirm = false } },
      }
end

return M