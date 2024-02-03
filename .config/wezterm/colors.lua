-- reference: https://github.com/aperum/dotfiles/blob/main/.config/wezterm/colors.lua

local wezterm = require("wezterm")

local M = {}

function M.apply_to_config(config)
    config.color_scheme = "Atom"

    config.window_background_opacity = 0.98
      
end

return M