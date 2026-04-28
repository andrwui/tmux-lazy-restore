#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT="$CURRENT_DIR/scripts/tmux-session-manager.sh"

get_tmux_option() {
  local option_name="$1"
  local default_value="$2"
  local option_value=$(tmux show-option -gqv "$option_name")
  if [ -z "$option_value" ]; then
    echo "$default_value"
  else
    echo "$option_value"
  fi
}

# Keybindings
choose_key=$(get_tmux_option "@tmux-lazy-restore-choose-key" "f")
revert_key=$(get_tmux_option "@tmux-lazy-restore-revert-key" "r")
delete_key=$(get_tmux_option "@tmux-lazy-restore-delete-key" "X")
restore_all_key=$(get_tmux_option "@tmux-lazy-restore-restore-all-key" "C-r")
save_all_key=$(get_tmux_option "@tmux-lazy-restore-save-all-key" "C-s")

tmux bind-key "$choose_key" run-shell "bash $SCRIPT choose"
tmux bind-key "$revert_key" run-shell "bash $SCRIPT revert"
tmux bind-key "$delete_key" run-shell "bash $SCRIPT delete"
tmux bind-key "$restore_all_key" run-shell "bash $SCRIPT restore_all"
tmux bind-key "$save_all_key" run-shell "bash $SCRIPT save_all"

# Auto-save hooks
tmux set-hook -g after-new-window "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g after-kill-pane "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g after-split-window "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g after-rename-window "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g session-created "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g session-closed "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g window-linked "run-shell 'bash $SCRIPT auto_save'"
tmux set-hook -g window-unlinked "run-shell 'bash $SCRIPT auto_save'"

# Startup: ensure default session exists and restore last active
run-shell "bash $SCRIPT startup"