-- reference: https://github.com/aperum/dotfiles/blob/main/.config/wezterm/font.lua

local wezterm = require("wezterm")

local M = {}

local function font_with_fallback(name, params)
	local names = { name, "Hack Nerd Font Mono", "Hack" }
	return wezterm.font_with_fallback(names, params)
end

function M.apply_to_config(config)
    if wezterm.target_triple == 'x86_64-pc-windows-msvc' or wezterm.target_triple == 'aarch64-apple-darwin' then
        local term_font = "FiraMono Nerd Font Mono"
    else
        local term_font = "FiraMono Nerd Font"
    end

	config.font_size = 14
	config.line_height = 1.0
	config.font = font_with_fallback(term_font)
	config.font_rules = {
		{
			italic = true,
			font = font_with_fallback(term_font, { italic = true }),
		},
		{
			italic = true,
			intensity = "Bold",
			font = font_with_fallback(term_font, { bold = true, italic = true }),
		},
		{
			intensity = "Bold",
			font = font_with_fallback(term_font, { bold = true }),
		},
	}
end

return M