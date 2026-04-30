#!/bin/bash

write_session_file() {
  local tmp="${SESSION_FILE}.tmp.$$"
  cat > "$tmp" && mv "$tmp" "$SESSION_FILE"
}

save_sessions() {
  local lock="${SESSION_FILE}.lock"
  {
    flock -n 9 || return 0
  } 9>"$lock"

  if [ "$QUIET" != "1" ]; then
    start_spinner_with_message "SAVING ALL SESSIONS"
  fi

  jq '(.sessions[] | .active) = "0"' "$SESSION_FILE" | write_session_file

  tmux list-sessions -F "#{session_name}:#{session_id}" | while IFS=: read -r session_name session_id; do
    session_active=0
    if [ "$session_name" == "$(tmux display-message -p '#{session_name}')" ]; then
        session_active=1;
    fi

    updated_session_data=$(get_session_data "$session_name" "$session_id" "$session_active")

    if [ -z "$updated_session_data" ] || ! echo "$updated_session_data" | jq '.' > /dev/null 2>&1; then
      continue
    fi

    existing_session_data=$(jq --arg session_name "$session_name" '.sessions[] | select(.name == $session_name)' "$SESSION_FILE")

    if [ -n "$existing_session_data" ]; then
      jq --arg session_name "$session_name" --argjson new_data "$updated_session_data" '.sessions |= map(if .name == $session_name then $new_data else . end)' "$SESSION_FILE" | write_session_file
    else
      jq --argjson new_data "$updated_session_data" '.sessions += [$new_data]' "$SESSION_FILE" | write_session_file
    fi
  done

  jq '.' "$SESSION_FILE" | write_session_file

  if [ "$QUIET" != "1" ]; then
    stop_spinner_with_message "SESSION SAVED"
  fi
}

get_session_data() {
  session_name=$1
  session_id=$2
  session_active=$3

  local windows_json="[]"
  while IFS=: read -r window_index window_name window_id window_active window_zoomed_flag window_layout; do
    local panes_json="[]"
    while IFS=: read -r pane_index pane_id pane_active pane_current_path pane_pid; do
      local pane_command=$(ps --ppid "$pane_pid" -o args= 2>/dev/null | sed 's/"/\\"/g' | sed 's/\n//')
      if [[ "$pane_command" == *"tmux-session-manager"* ]]; then
        pane_command=""
      fi
      local pane_json=$(jq -n \
        --arg index "$pane_index" \
        --arg active "$pane_active" \
        --arg path "$pane_current_path" \
        --arg command "$pane_command" \
        '{index: ($index|tonumber), active: $active, path: $path, command: $command}')
      panes_json=$(echo "$panes_json" | jq --argjson p "$pane_json" '. += [$p]')
    done < <(tmux list-panes -t "$window_id" -F "#{pane_index}:#{pane_id}:#{pane_active}:#{pane_current_path}:#{pane_pid}")

    local window_json=$(jq -n \
      --arg index "$window_index" \
      --arg name "$window_name" \
      --arg active "$window_active" \
      --arg zoomed "$window_zoomed_flag" \
      --arg layout "$window_layout" \
      --argjson panes "$panes_json" \
      '{index: ($index|tonumber), name: $name, active: $active, zoomed: $zoomed, layout: $layout, panes: $panes}')
    windows_json=$(echo "$windows_json" | jq --argjson w "$window_json" '. += [$w]')
  done < <(tmux list-windows -t "$session_id" -F "#{window_index}:#{window_name}:#{window_id}:#{window_active}:#{window_zoomed_flag}:#{window_layout}")

  jq -n \
    --arg name "$session_name" \
    --arg active "$session_active" \
    --argjson windows "$windows_json" \
    '{name: $name, active: $active, windows: $windows}'
}

restore_sessions() {
  restore_session_name=$1
  force_restore=$2

  active_session_name=""
  active_session_window_index=""
  active_session_pane_index=""

  initial_session_count=$(tmux list-sessions | wc -l)
  initial_window_count=$(tmux list-windows | wc -l)
  initial_pane_count=$(tmux list-panes | wc -l)

  current_session_name=$(tmux display-message -p '#{session_name}')
  current_window_id=$(tmux display-message -p '#{window_id}')
  current_pane_id=$(tmux display-message -p '#{pane_id}')

  if [ -n "$restore_session_name" ]; then
    start_spinner_with_message "RESTORING: $restore_session_name"
    if tmux has-session -t="$restore_session_name" 2>/dev/null && [ "$force_restore" != "true" ]; then
      tmux switch-client -Z -t="${restore_session_name}"
      stop_spinner_with_message "SESSION ALREADY RUNNING"
      return
    fi
    sessions=$(jq -c --arg restore_session_name "$restore_session_name" '.sessions[] | select(.name == $restore_session_name)' "$SESSION_FILE")
  else
    start_spinner_with_message "RESTORING ALL SESSIONS"
    sessions=$(jq -c '.sessions[]' "$SESSION_FILE")
  fi

  while IFS= read -r session; do
    session_name=$(jq -r '.name' <<< "$session")
    session_active=$(jq -r '.active' <<< "$session")
    active_window_index=""

    if tmux has-session -t="$session_name" 2>/dev/null; then
      if [ "$force_restore" != "true" ]; then
        continue
      fi
      if [ "$session_name" != "$current_session_name" ]; then
        tmux kill-session -t="$session_name"
        tmux new-session -d -s "$session_name"
      else
        clear_session_contents "$current_session_name" "$current_window_id" "$current_pane_id"
      fi
    else
      tmux new-session -d -s "$session_name"
    fi

    windows=$(jq -c '.windows[]' <<< "$session")
    while IFS= read -r window; do
      window_index=$(jq -r '.index' <<< "$window")
      window_name=$(jq -r '.name' <<< "$window")
      window_active=$(jq -r '.active' <<< "$window")
      window_zoomed_flag=$(jq -r '.zoomed' <<< "$window")
      window_layout=$(jq -r '.layout' <<< "$window")
      active_window_pane_index=""

      if [ "$window_index" -gt 0 ]; then
        tmux new-window -d -t="$session_name" -n "$window_name"
      else
        tmux rename-window -t="$session_name:$window_index" "$window_name"
      fi

      tmux select-window -t="$session_name:$window_index"

      panes=$(jq -c '.panes[]' <<< "$window")
      while IFS= read -r pane; do
        pane_index=$(jq -r '.index' <<< "$pane")
        pane_path=$(jq -r '.path' <<< "$pane")
        pane_active=$(jq -r '.active' <<< "$pane")
        pane_command=$(jq -r '.command' <<< "$pane")

        if [[ ("$session_active" == "1" || -n "$restore_session_name" || "$active_session_name" == "") && "$window_active" == "1" && "$pane_active" == "1" ]]; then
          active_session_name=$session_name
          active_session_window_index=$window_index
          active_session_pane_index=$pane_index
        fi
        if [[ "$window_active" == "1" && "$pane_active" == "1" ]]; then
          active_window_index=$window_index
          active_window_pane_index=$pane_index
        fi
        if [[ "$pane_active" == "1" ]]; then
          active_pane_index=$pane_index
        fi

        if [ "$pane_index" -gt 0 ]; then
          tmux split-window -t="${session_name}:${window_index}" -c "$pane_path"
        fi                

        if [ -n "$pane_path" ] && [ -n "$pane_command" ]; then
          tmux send-keys -t="$session_name:$window_index.$pane_index" "cd \"$pane_path\"" C-m "$pane_command" C-m
        elif [ -n "$pane_command" ]; then
          tmux send-keys -t="$session_name:$window_index.$pane_index" "$pane_command" C-m
        elif [ -n "$pane_path" ]; then
          tmux send-keys -t="$session_name:$window_index.$pane_index" "cd \"$pane_path\"" C-m "clear" C-m
        fi
      done <<< "$panes"

      tmux select-layout -t="$session_name:$window_index" "$window_layout"
      tmux select-pane -t="$session_name:$window_index.$active_pane_index"
      if [[ "$window_zoomed_flag" == "1" && -n "$active_pane_index" ]]; then
        tmux resize-pane -t="$session_name:$window_index.$active_pane_index" -Z
      fi
    done <<< "$windows"

    tmux select-window -t="$session_name:$active_window_index.$active_window_pane_index"

  done <<< "$sessions"

  if [ -n "$active_session_name" ]; then
    tmux switch-client -Z -t="${active_session_name}:${active_session_window_index}.${active_session_pane_index}"

    if [ "$KILL_LAUNCH_SESSION" == "on" ] && [ "$active_session_name" != "$current_session_name" ] && [ "$initial_session_count" -eq 1 ] && [ "$initial_window_count" -eq 1 ] && [ "$initial_pane_count" -eq 1 ] && [[ "$current_session_name" =~ ^[0-9]+$ ]]; then
      tmux kill-session -t $current_session_name
    fi
  fi

  stop_spinner_with_message "SESSION(S) RESTORED"
}

choose_session() {
    file_sessions_string=$(jq -r '.sessions | .[].name' "$SESSION_FILE")
    declare -A file_sessions
    if [ -n "$file_sessions_string" ]; then
      while IFS= read -r session_name; do
        file_sessions[$session_name]=1
      done <<< "$file_sessions_string"
    fi

    declare -A active_sessions
    while IFS= read -r session_name; do
      active_sessions[$session_name]=1
    done <<< $(tmux list-sessions -F "#{session_name}")

    total_count=0
    for session_name in "${!file_sessions[@]}"; do
      total_count=$((total_count + 1))
    done
    for session_name in "${!active_sessions[@]}"; do
      if [[ ! -v file_sessions[$session_name] ]]; then
        total_count=$((total_count + 1))
      fi
    done

    chooser_sessions=""
    for session_name in "${!file_sessions[@]}"; do
      if [[ -v active_sessions[$session_name] ]]; then
        chooser_sessions+="$session_name 󰄬\n"
      else
        chooser_sessions+="$session_name 󰒲\n"
      fi
    done
    for session_name in "${!active_sessions[@]}"; do
      if [[ ! -v file_sessions[$session_name] ]]; then
        chooser_sessions+="$session_name 󰜥\n"
      fi
    done

    chooser_sessions=${chooser_sessions%\\n}
    chooser_sessions=$(echo -e "$chooser_sessions" | sort)

    POPUP_HEIGHT=$((total_count + 4))
    TMPFILE=$(mktemp /tmp/tmux-lazy-restore-fzf.XXXXXX)

    tmux popup -E -w "15%" -h "$POPUP_HEIGHT" -d '#{pane_current_path}' "
      echo \"${chooser_sessions}\" | fzf --reverse --border=none --no-info --no-scrollbar --prompt='session > ' --color=bw --expect=ctrl-r,ctrl-k,ctrl-a,ctrl-l,ctrl-u --bind 'esc:abort' > $TMPFILE
    "

    if [ -s "$TMPFILE" ]; then
      KEY=$(head -1 "$TMPFILE")
      SELECTION=$(head -2 "$TMPFILE" | tail -1 | sed 's/ 󰄬$\| 󰒲$\| 󰜥$//')
      rm -f "$TMPFILE"

      if [ "$KEY" = "ctrl-a" ]; then
        before_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
        tmux popup -E -w "40%" -h "60%" -d '#{pane_current_path}' "fish -c 'tn'"
        after_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null)
        new_sessions=$(comm -23 <(echo "$after_sessions" | sort) <(echo "$before_sessions" | sort))
        while IFS= read -r new_session; do
          [ -z "$new_session" ] && continue
          session_id=$(tmux list-sessions -F '#{session_name}:#{session_id}' | grep "^${new_session}:" | cut -d: -f2)
          new_session_data=$(get_session_data "$new_session" "$session_id" "0")
          if [ -n "$new_session_data" ] && echo "$new_session_data" | jq '.' > /dev/null 2>&1; then
            jq --argjson new_data "$new_session_data" '.sessions += [$new_data]' "$SESSION_FILE" | write_session_file
          fi
        done <<< "$new_sessions"
      elif [ "$KEY" = "ctrl-r" ] && [ -n "$SELECTION" ]; then
        RENAME_RESULT=$(mktemp /tmp/tmux-lazy-restore-rename.XXXXXX)
        tmux popup -E -w "30%" -h "3" -d '#{pane_current_path}' "read -p 'new name: ' NEWNAME; echo \"\$NEWNAME\" > $RENAME_RESULT"
        NEW_NAME=$(cat "$RENAME_RESULT" | tr -d '\n')
        rm -f "$RENAME_RESULT"
        if [ -n "$NEW_NAME" ] && [ "$NEW_NAME" != "$SELECTION" ]; then
          if tmux has-session -t="$SELECTION" 2>/dev/null; then
            tmux rename-session -t "$SELECTION" "$NEW_NAME"
          fi
          jq --arg old "$SELECTION" --arg new "$NEW_NAME" '(.sessions[] | select(.name == $old) | .name) = $new' "$SESSION_FILE" | write_session_file
        fi
      elif [ "$KEY" = "ctrl-k" ] && [ -n "$SELECTION" ]; then
        jq --arg name "$SELECTION" 'del(.sessions[] | select(.name == $name))' "$SESSION_FILE" | write_session_file
        tmux kill-session -t "$SELECTION"
        save_sessions
      elif [ "$KEY" = "ctrl-l" ] && [ -n "$SELECTION" ]; then
        restore_sessions "$SELECTION" "true"
        set_last_active "$SELECTION"
      elif [ "$KEY" = "ctrl-u" ] && [ -n "$SELECTION" ]; then
        if tmux has-session -t="$SELECTION" 2>/dev/null; then
          if [ "$(tmux list-sessions | wc -l)" -gt 1 ]; then
            tmux switch-client -l
          fi
          tmux kill-session -t "$SELECTION"
        fi
      elif [ -n "$SELECTION" ]; then
        restore_sessions "$SELECTION" "false"
        set_last_active "$SELECTION"
      fi
    else
      rm -f "$TMPFILE"
    fi
}

revert_session() {
  session_name=$(tmux display-message -p '#{session_name}')
  current_session_id=$(tmux display-message -p '#{session_id}')
  restore_sessions "$session_name" "true"
}

delete_session() {
  session_name=$(tmux display-message -p '#{session_name}')

  jq --arg session_name "$session_name" 'del(.sessions[] | select(.name == $session_name))' "$SESSION_FILE" | write_session_file

  if [ "$(tmux list-sessions | wc -l)" -gt 1 ]; then
    tmux switch-client -l
  fi

  tmux kill-session -t="$session_name" 2>/dev/null

  stop_spinner_with_message "SESSION DELETED"
}

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

clear_session_contents() {
  current_session_name=$1
  current_window_id=$2
  current_pane_id=$3

  tmux list-windows -t="$current_session_name" -F "#{window_name}:#{window_id}" | while IFS=: read -r window_name window_id; do
    if [ "$window_id" != "$current_window_id" ]; then
      tmux kill-window -t="$current_session_name:$window_id"
    fi
  done

  tmux list-panes -t="$current_session_name:$current_window_id" -F "#{pane_id}" | while IFS= read -r pane_id; do
    if [ "$pane_id" != "$current_pane_id" ]; then
      tmux kill-pane -t "$pane_id"
    else
      kill -KILL "$(get_pane_pid $current_pane_id)" 2>/dev/null
    fi
  done
}

get_pane_pid() {
  pane_id=$1
  local pane_pid=$(tmux display-message -p -t "$pane_id" "#{pane_pid}")

  ps -ao "ppid pid" |
    sed "s/^ *//" |
    grep "^${pane_pid}" |
    cut -d' ' -f2- |
    head -n 1
}

set_last_active() {
  local session_name="$1"
  if ! jq -e 'has("last_active")' "$SESSION_FILE" > /dev/null 2>&1; then
    jq '. + {"last_active":""}' "$SESSION_FILE" | write_session_file
  fi
  jq --arg name "$session_name" '.last_active = $name' "$SESSION_FILE" | write_session_file
}

start_spinner_with_message() {
	$CURRENT_DIR/spinner.sh "$1" &
	export SPINNER_PID=$!
}

stop_spinner_with_message() {
  STOP_MESSAGE=$1
	kill $SPINNER_PID
}

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SESSION_FILE=$(get_tmux_option @tmux-lazy-restore-session-file "$HOME/.config/tmux-lazy-restore/sessions.json")

if [ ! -f "$SESSION_FILE" ]; then
  mkdir -p "$(dirname "$SESSION_FILE")"
  echo '{"last_active":"","sessions":[]}' > "$SESSION_FILE"
fi

KILL_LAUNCH_SESSION=$(get_tmux_option @tmux-lazy-restore-kill-launch-session "off")

case "$1" in
    choose)
        choose_session
        ;;
    revert)
        revert_session
        ;;
    delete)
        delete_session
        ;;
    save_all)
        save_sessions
        ;;
    auto_save)
        QUIET=1 save_sessions
        ;;
    restore_all)
        restore_sessions
        ;;
    startup)
        if [ "$(tmux list-sessions 2>/dev/null | wc -l)" -eq 1 ]; then
            target=$(jq -r '.last_active' "$SESSION_FILE")
            if [ -z "$target" ] || [ "$target" = "null" ]; then
                target=$(jq -r '.sessions[0].name' "$SESSION_FILE")
            fi
            if [ -n "$target" ] && [ "$target" != "null" ]; then
                restore_sessions "$target" "false"
            fi
        fi
        ;;
    *)
        echo "Usage: $0 {choose|revert|delete|save_all|auto_save|restore_all|startup}"
        exit 1
        ;;
esac