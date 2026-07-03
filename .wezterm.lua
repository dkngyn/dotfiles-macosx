local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- Solarized palette (mirrors ~/.tmux.conf)
local solarized = {
  base2 = "#eee8d5",
  base0 = "#839496",
  base02 = "#073642",
  base03 = "#002b36",
  blue = "#268bd2",
  violet = "#6c71c4",
  cyan = "#2aa198",
  green = "#859900",
  orange = "#cb4b16",
  red = "#dc322f",
  magenta = "#d33682",
  yellow = "#b58900",
}

config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 16

config.color_scheme = "Solarized Dark (Gogh)"

config.enable_tab_bar = true
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_and_split_indices_are_zero_based = false
config.window_decorations = "TITLE | RESIZE"

config.colors = {
  tab_bar = {
    background = solarized.base02, -- full-width bar strip (lighter than terminal bg)
    active_tab = { bg_color = solarized.cyan, fg_color = solarized.base03 },
    inactive_tab = { bg_color = solarized.base02, fg_color = solarized.base0 },
    new_tab = { bg_color = solarized.base02, fg_color = solarized.base0 },
  },
}

config.window_padding = {
  top = 0,
  bottom = 0,
}

config.scrollback_lines = 10000

-- cached CPU / memory usage, refreshed periodically (shelling out is sync, so throttle)
local sys = { cpu = "?", mem = "?", tick = 0 }

local function run(cmd)
  local ok, stdout = pcall(function()
    local _, out = wezterm.run_child_process({ "/bin/sh", "-c", cmd })
    return out
  end)
  if ok and stdout and stdout ~= "" then
    return (stdout:gsub("%s+$", ""))
  end
  return nil
end

local function refresh_sys()
  local cpu = run("ps -A -o %cpu= | awk -v n=$(sysctl -n hw.ncpu) '{s+=$1} END{printf \"%.0f\", s/n}'")
  local mem = run("memory_pressure 2>/dev/null | awk -F: '/free percentage/{gsub(/[ %]/,\"\",$2); printf \"%.0f\", 100-$2}'")
  if cpu then sys.cpu = cpu end
  if mem then sys.mem = mem end
end

-- status bar: leader indicator on the left, info widgets on the right
wezterm.on("update-status", function(window, _)
  -- refresh CPU/mem every ~5s (handler fires ~1/s)
  sys.tick = sys.tick + 1
  if sys.tick % 5 == 1 then
    refresh_sys()
  end

  -- left: leader indicator (🌊 while leader is pending)
  local prefix = ""
  if window:leader_is_active() then
    prefix = " 🌊 "
  end
  window:set_left_status(wezterm.format({
    { Foreground = { Color = solarized.yellow } },
    { Text = prefix },
  }))

  -- right: workspace name | battery | time
  local battery = ""
  for _, b in ipairs(wezterm.battery_info()) do
    battery = string.format("%.0f%%", b.state_of_charge * 100)
  end

  window:set_right_status(wezterm.format({
    { Foreground = { Color = solarized.green } },
    { Text = "[" .. window:active_workspace() .. "]  " },
    { Foreground = { Color = solarized.blue } },
    { Text = "" .. " " .. sys.cpu .. "%  " },
    { Foreground = { Color = solarized.violet } },
    { Text = "" .. " " .. sys.mem .. "%  " },
    { Foreground = { Color = solarized.magenta} },
    { Text = battery ~= "" and ("" .. " " .. battery .. "  ") or "" },
    { Foreground = { Color = solarized.base0 } },
    { Text = wezterm.strftime("%b %d %H:%M") .. " " },
  }))
end)

-- tab title shows the foreground process name (not the cwd)
wezterm.on("format-tab-title", function(tab, _, _, _, _, _)
  local title = tab.tab_title -- manual rename (LEADER ,) wins
  if not title or title == "" then
    local proc = tab.active_pane.foreground_process_name or ""
    title = proc:match("([^/\\]+)$") or tab.active_pane.title
  end
  return " " .. (tab.tab_index + 1) .. ": " .. title .. " "
end)

-- tmux-style key bindings (mirrors ~/.tmux.conf, prefix C-x)
config.leader = { key = "x", mods = "CTRL", timeout_milliseconds = 1000 }
config.keys = {
  -- new window/tab
  { mods = "LEADER", key = "c", action = wezterm.action.SpawnTab("CurrentPaneDomain") },

  -- split panes (| = horizontal/side-by-side, _ = vertical/stacked)
  { mods = "LEADER", key = "|", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { mods = "LEADER", key = "_", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },

  -- vim-style pane navigation (hjkl + arrow keys)
  { mods = "LEADER", key = "h", action = wezterm.action.ActivatePaneDirection("Left") },
  { mods = "LEADER", key = "j", action = wezterm.action.ActivatePaneDirection("Down") },
  { mods = "LEADER", key = "k", action = wezterm.action.ActivatePaneDirection("Up") },
  { mods = "LEADER", key = "l", action = wezterm.action.ActivatePaneDirection("Right") },
  { mods = "LEADER", key = "LeftArrow", action = wezterm.action.ActivatePaneDirection("Left") },
  { mods = "LEADER", key = "DownArrow", action = wezterm.action.ActivatePaneDirection("Down") },
  { mods = "LEADER", key = "UpArrow", action = wezterm.action.ActivatePaneDirection("Up") },
  { mods = "LEADER", key = "RightArrow", action = wezterm.action.ActivatePaneDirection("Right") },

  -- vi copy mode
  { mods = "LEADER", key = "[", action = wezterm.action.ActivateCopyMode },

  -- zoom/unzoom current pane (tmux: prefix z)
  { mods = "LEADER", key = "z", action = wezterm.action.TogglePaneZoomState },

  -- swap panes: rotate (tmux: prefix { / }) or pick one to swap with active
  { mods = "LEADER", key = "{", action = wezterm.action.RotatePanes("CounterClockwise") },
  { mods = "LEADER", key = "}", action = wezterm.action.RotatePanes("Clockwise") },
  { mods = "LEADER", key = "s", action = wezterm.action.PaneSelect({ mode = "SwapWithActive" }) },

  -- send literal C-x to the shell (tmux: bind-key C-x send-prefix)
  { mods = "LEADER|CTRL", key = "x", action = wezterm.action.SendKey({ key = "x", mods = "CTRL" }) },

  -- workspaces (tmux sessions)
  { mods = "LEADER", key = "w", action = wezterm.action_callback(function(window, pane)
    local choices = {}
    for _, name in ipairs(wezterm.mux.get_workspace_names()) do
      choices[#choices + 1] = { id = name, label = name }
    end
    window:perform_action(wezterm.action.InputSelector({
      title = "Select workspace",
      choices = choices,
      fuzzy = true,
      action = wezterm.action_callback(function(inner_window, inner_pane, id, _)
        if id then
          inner_window:perform_action(wezterm.action.SwitchToWorkspace({ name = id }), inner_pane)
        end
      end),
    }), pane)
  end) },
  -- create a new named workspace (tmux: new session)
  { mods = "LEADER", key = "W", action = wezterm.action.PromptInputLine({
    description = "New workspace name:",
    action = wezterm.action_callback(function(window, pane, line)
      if line and line ~= "" then
        window:perform_action(wezterm.action.SwitchToWorkspace({ name = line }), pane)
      end
    end),
  }) },
  { mods = "LEADER", key = "(", action = wezterm.action.SwitchWorkspaceRelative(-1) },
  { mods = "LEADER", key = ")", action = wezterm.action.SwitchWorkspaceRelative(1) },
  { mods = "LEADER", key = "$", action = wezterm.action.PromptInputLine({
    description = "Rename workspace:",
    action = wezterm.action_callback(function(window, _, line)
      if line and line ~= "" then
        wezterm.mux.rename_workspace(window:active_workspace(), line)
      end
    end),
  }) },

  -- rename current tab (tmux: prefix ,)
  { mods = "LEADER", key = ",", action = wezterm.action.PromptInputLine({
    description = "Rename tab:",
    action = wezterm.action_callback(function(window, pane, line)
      if line then
        window:active_tab():set_title(line)
      end
    end),
  }) },
}

-- LEADER + number to jump to that tab (1-based, like tmux)
for i = 1, 9 do
  table.insert(config.keys, {
    mods = "LEADER",
    key = tostring(i),
    action = wezterm.action.ActivateTab(i - 1),
  })
end

return config
