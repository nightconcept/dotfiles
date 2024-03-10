-- reference: https://github.com/aperum/dotfiles/blob/main/.config/wezterm/colors.lua

local wezterm = require("wezterm")

local M = {}

function M.apply_to_config(config)
	config.color_scheme = "Solarized Osaka"

	config.window_background_opacity = 0.97
end

return M
