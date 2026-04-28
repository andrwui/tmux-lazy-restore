# Tmux Lazy Restore

> A fork of [bcampolo/tmux-lazy-restore](https://github.com/bcampolo/tmux-lazy-restore)

A tmux session manager that allows sessions to be lazily restored in order to save memory and processing power, when compared to other session managers which generally restore all of your sessions at once.

This fork runs as standalone scripts instead of a TPM plugin, with a popup-style fzf session picker, in-picker keybindings for rename/kill/new session, and automatic session state saving on window/pane changes.

## Features

- **Default Session**: A `default` session is always present and loaded at startup in `~`. It cannot be deleted or unloaded, ensuring you never end up with a bare numeric session.
- **Lazily Restore Individual Sessions**: A custom fzf popup lets you select any session from the saved session file and only that session will be restored.
- **Session Picker Keybindings**: Inside the session picker:
  - `Enter` - Switch to / restore the selected session
  - `Ctrl-r` - Rename the selected session (updates both tmux and the session file)
  - `Ctrl-k` - Kill the selected session (removes from tmux and the session file, then auto-saves remaining state)
  - `Ctrl-l` - Force-load / revert the selected session from the session file
  - `Ctrl-u` - Unload the selected session (kills tmux session, keeps in file)
  - `Ctrl-a` - Create a new session (auto-saved to the session file)
  - `Esc` - Abort
- **Session Markers**:  loaded from file,  saved but not loaded,  live but not saved.
- **Auto-Save**: Session state is automatically saved on window creation, window close, window rename, pane split, pane kill, and session create/close.
- **Easy-to-Read JSON Format**: Session files are stored in human-readable JSON and can be edited by hand.
- **Bulk Session Operations**: Save All and Restore All are also available.
- **Last Active Tracking**: Remembers your last active session and restores it on tmux startup.

## Requirements

- [tmux](https://github.com/tmux/tmux/wiki)
- [fzf](https://github.com/junegunn/fzf)
- [jq](https://github.com/jqlang/jq)

## Installation

Add the keybindings to your `~/.tmux.conf`:

```sh
bind-key f run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh choose'
bind-key r run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh revert'
bind-key X run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh delete'
bind-key C-r run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh restore_all'
bind-key C-s run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh save_all'
```

## Auto-Save Hooks

Add these hooks to `~/.tmux.conf` to automatically save session state on changes:

```sh
set-hook -g after-new-window 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g after-kill-pane 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g after-split-window 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g after-rename-window 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g session-created 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g session-closed 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g window-linked 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
set-hook -g window-unlinked 'run-shell "bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh auto_save"'
```

## Startup

Add this to your `~/.tmux.conf` to auto-restore your last active session and ensure the `default` session is always present:

```sh
run-shell 'bash ~/.config/tmux/tmux-lazy-restore/scripts/tmux-session-manager.sh startup'
```

## Key Bindings

- `prefix + f` - Fuzzy find a session (restore if not already loaded, switch to if loaded)
- `prefix + r` - Revert the current session to its saved state
- `prefix + X` - Delete the current session and remove it from the session file
- `prefix + Ctrl-r` - Restore all sessions
- `prefix + Ctrl-s` - Save all sessions

## Session File

Sessions are stored by default at `~/.config/tmux-lazy-restore/sessions.json`. To change the path, set the `@tmux-lazy-restore-session-file` tmux option before the script runs, or edit the `SESSION_FILE` variable in `tmux-session-manager.sh`.

## Differences from Upstream

- Runs as standalone bash scripts instead of a TPM plugin
- A `default` session is always present, loaded at startup, and cannot be deleted
- Session picker uses an fzf popup styled like a minimal tmux menu (`--reverse`, `--border=none`, `--no-info`, `--no-scrollbar`, `--color=bw`)
- In-picker keybindings for rename (`Ctrl-r`), kill (`Ctrl-k`), force-load (`Ctrl-l`), unload (`Ctrl-u`), and new session (`Ctrl-a`)
- Rename and kill operations update the session file immediately
- Auto-save hooks for window/pane/session changes (no spinner, silent)
- Last active session tracking for smarter startup restoration
- No status bar messages on save/restore