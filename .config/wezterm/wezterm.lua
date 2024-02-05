
-- References: [dotfiles/.config/wezterm at main · aperum/dotfiles](https://github.com/aperum/dotfiles/tree/main/.config/wezterm)
local wezterm = require('wezterm')
local keybinds = require("keybinds")
local font = require("font")
local colors = require("colors")
local mousebinds = require("mousebinds")

local config = {}
if wezterm.config_builder then
  config = wezterm.config_builder()
end

keybinds.apply_to_config(config)
font.apply_to_config(config)
colors.apply_to_config(config)
mousebinds.apply_to_config(config)

-- general random config
config.scrollback_lines = 7000
config.hyperlink_rules = wezterm.default_hyperlink_rules()
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = 'NeverPrompt'

return config
