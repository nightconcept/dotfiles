-- References: [dotfiles/.config/wezterm at main · aperum/dotfiles](https://github.com/aperum/dotfiles/tree/main/.config/wezterm)

-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}
if wezterm.config_builder then
  config = wezterm.config_builder()
end

-- font.lua
local function font_with_fallback(name, params)
  local names = { name, "Hack Nerd Font Mono" }
  return wezterm.font_with_fallback(names, params)
end

local term_font = "FiraMono Nerd Font"
if wezterm.target_triple == 'x86_64-pc-windows-msvc' or wezterm.target_triple == 'aarch64-apple-darwin' then
  term_font = "FiraMono Nerd Font Mono"
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

-- colors.lua
config.color_scheme = "Tokyo Night"
config.window_background_opacity = 0.97

-- keybinds.lua
if wezterm.target_triple == 'x86_64-pc-windows-msvc' or wezterm.target_triple == 'aarch64-apple-darwin' then
  config.keys = {
    -- Terminal-level operations
    { key = 't', mods = 'CMD', action = act.SpawnTab('CurrentPaneDomain') },
    { key = 'w', mods = 'CMD', action = act.CloseCurrentTab { confirm = true } },
    { key = 'Enter', mods = 'CMD', action = act.ToggleFullScreen },
    
    -- Tab navigation
    { key = '{', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(-1) },
    { key = '}', mods = 'CMD|SHIFT', action = act.ActivateTabRelative(1) },
    
    -- Don't bind Cmd+1-9 (let Aerospace handle workspace switching)
    -- Don't bind Ctrl+t (let Zellij handle multiplexing)
    
    -- Keep some useful terminal shortcuts that don't conflict
    { key = 'k', mods = 'CMD', action = act.ClearScrollback('ScrollbackAndViewport') },
    { key = 'r', mods = 'CMD', action = act.ReloadConfiguration },
  }
else
    config.keys = {
    -- Terminal-level operations
    { key = 't', mods = 'CTRL', action = act.SpawnTab('CurrentPaneDomain') },
    { key = 'w', mods = 'CTRL', action = act.CloseCurrentTab { confirm = true } },
    { key = 'Enter', mods = 'CTRL', action = act.ToggleFullScreen },
    
    -- Tab navigation
    { key = '{', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
    { key = '}', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(1) },
    
    -- Don't bind Cmd+1-9 (let Aerospace handle workspace switching)
    -- Don't bind Ctrl+t (let Zellij handle multiplexing)
    
    -- Keep some useful terminal shortcuts that don't conflict
    { key = 'k', mods = 'CTRL', action = act.ClearScrollback('ScrollbackAndViewport') },
    { key = 'r', mods = 'CTRL', action = act.ReloadConfiguration },
  }
end
-- mousebinds.lua
config.mouse_bindings = {
  -- Change the default click behavior so that it only selects
  -- text and doesn't open hyperlinks
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'ClipboardAndPrimarySelection',
  },

  -- and make CMD-Click open hyperlinks
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CMD',
    action = act.OpenLinkAtMouseCursor,
  },
  {
    event = { Down = { streak = 3, button = 'Left' } },
    action = wezterm.action.SelectTextAtMouseCursor 'SemanticZone',
    mods = 'NONE',
  },
  -- Make CTRL-Click open hyperlinks on Linux/NixOS
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.OpenLinkAtMouseCursor,
  },
}

-- Disable middle-click closing tabs on Linux only
if wezterm.target_triple:find("linux") then
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = 'Middle' } },
    mods = 'NONE',
    action = act.Nop,  -- Do nothing on middle click
  })
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = 'Middle' } },
    mods = 'NONE',
    action = act.Nop,  -- Do nothing on middle click
  })
end

-- general random config
config.scrollback_lines = 7000
config.hyperlink_rules = wezterm.default_hyperlink_rules()
config.hide_tab_bar_if_only_one_tab = true
config.window_close_confirmation = 'NeverPrompt'

-- Set to PowerShell for Windows
if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  config.default_prog = { 'pwsh.exe', '-NoLogo' }
end

-- Windows clipboard shortcuts use the system clipboard across windows and apps.
if wezterm.target_triple:find('windows', 1, true) then
  table.insert(config.keys, {
    key = 'c',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      if window:get_selection_text_for_pane(pane) ~= '' then
        window:perform_action(act.CopyTo 'Clipboard', pane)
        window:perform_action(act.ClearSelection, pane)
      else
        window:perform_action(act.SendKey { key = 'c', mods = 'CTRL' }, pane)
      end
    end),
  })
  table.insert(config.keys, { key = 'v', mods = 'CTRL', action = act.PasteFrom 'Clipboard' })
  table.insert(config.keys, { key = 'Insert', mods = 'CTRL', action = act.CopyTo 'Clipboard' })
  table.insert(config.keys, { key = 'Insert', mods = 'SHIFT', action = act.PasteFrom 'Clipboard' })
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = 'Right' } },
    mods = 'NONE',
    action = act.PasteFrom 'Clipboard',
  })
end

return config
