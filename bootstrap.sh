#!/bin/bash

set -e

# --- Logging helpers ---
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

log_section() { printf "\n${BOLD}${BLUE}==> %s${RESET}\n" "$1"; }
log_info()    { printf "${GREEN}  [ok]${RESET} %s\n" "$1"; }
log_action()  { printf "${YELLOW}  [..]${RESET} %s\n" "$1"; }
log_skip()    { printf "${DIM}  [--] %s${RESET}\n" "$1"; }
log_warn()    { printf "${YELLOW}  [!!] %s${RESET}\n" "$1" >&2; }
log_error()   { printf "${RED}  [!!] %s${RESET}\n" "$1" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Bootstrap a macOS development environment by symlinking dotfiles,
installing packages, and configuring system settings.

With no flags, all sections run. Pass one or more flags to run only
those sections.

Options:
  -h, --help        Show this help message and exit
  --init            Run init.sh (git submodule setup)
  --homebrew        Install Homebrew and run brew bundle
  --symlinks        Clean up broken symlinks and link dotfiles
  --antidote        Install the Antidote zsh plugin manager
  --dotnet          Register side-by-side dotnet SDKs from Homebrew
  --macos           Apply macOS defaults (Dock, .osx)
  --ssh             Configure sshd PATH for non-interactive sessions
  --et              Start Eternal Terminal server at login
  --claude          Install Claude Code
  --iterm           Install iTerm2 AI plugin
  --tmux            Install tmux plugin manager (TPM) and plugins

Examples:
  $(basename "$0")                  # run everything
  $(basename "$0") --homebrew       # only install/update brew packages
  $(basename "$0") --symlinks --macos  # only symlinks and macOS defaults
EOF
    exit 0
}

# Parse flags
RUN_INIT=0
RUN_HOMEBREW=0
RUN_SYMLINKS=0
RUN_ANTIDOTE=0
RUN_DOTNET=0
RUN_MACOS=0
RUN_SSH=0
RUN_ET=0
RUN_CLAUDE=0
RUN_ITERM=0
RUN_TMUX=0
RUN_ALL=1

for arg in "$@"; do
    case "$arg" in
        -h|--help)     usage ;;
        --init)        RUN_INIT=1;     RUN_ALL=0 ;;
        --homebrew)    RUN_HOMEBREW=1;  RUN_ALL=0 ;;
        --symlinks)    RUN_SYMLINKS=1;  RUN_ALL=0 ;;
        --antidote)    RUN_ANTIDOTE=1;  RUN_ALL=0 ;;
        --dotnet)      RUN_DOTNET=1;    RUN_ALL=0 ;;
        --macos)       RUN_MACOS=1;     RUN_ALL=0 ;;
        --ssh)         RUN_SSH=1;       RUN_ALL=0 ;;
        --et)          RUN_ET=1;        RUN_ALL=0 ;;
        --claude)      RUN_CLAUDE=1;    RUN_ALL=0 ;;
        --iterm)       RUN_ITERM=1;     RUN_ALL=0 ;;
        --tmux)        RUN_TMUX=1;      RUN_ALL=0 ;;
        *) echo "Unknown option: $arg" >&2; echo "Run '$(basename "$0") --help' for usage." >&2; exit 1 ;;
    esac
done

should_run() {
    [ "$RUN_ALL" -eq 1 ] || [ "$(eval echo \$"RUN_$1")" -eq 1 ]
}

DOTFILES_DIR=$(cd "$(dirname "$0")" && pwd -P)

# --- Init ---
if should_run INIT; then
    log_section "Init"
    log_action "Running init.sh..."
    ./init.sh
    log_info "Init complete"
fi

# --- Homebrew install ---
if should_run HOMEBREW; then
    log_section "Homebrew"
    if ! [ -x "$(command -v /opt/homebrew/bin/brew)" ] > /dev/null; then
        log_action "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        log_info "Homebrew installed"
    else
        log_skip "Homebrew already installed"
    fi
fi

export PATH="/opt/homebrew/bin:$PATH"

# --- macOS defaults ---
if should_run MACOS; then
    log_section "macOS Defaults"
    log_action "Setting Dock to autohide..."
    defaults write com.apple.dock autohide -bool true && killall Dock || true
    log_info "Dock configured"
fi

# Remove broken symlinks pointing into dotfiles (shared or local)
cleanup_broken_symlinks() {
    local files_dir="$1"
    while read -r link; do
        target=$(readlink "$link")
        if [[ "$target" == "$files_dir/"* ]] && [ ! -e "$link" ]; then
            read -rp "Remove broken symlink: $link? [y/N] " confirm
            [[ "$confirm" =~ ^[Yy]$ ]] && rm "$link"
        fi
    done < <(find "$HOME" -maxdepth 1 -type l)

    for subdir in "$files_dir"/*/; do
        [ -d "$subdir" ] || continue
        rel="${subdir#"$files_dir/"}"
        rel="${rel%/}"
        home_subdir="$HOME/$rel"
        if [ -d "$home_subdir" ]; then
            while read -r link; do
                target=$(readlink "$link")
                if [[ "$target" == "$files_dir/"* ]] && [ ! -e "$link" ]; then
                    read -rp "Remove broken symlink: $link? [y/N] " confirm
                    [[ "$confirm" =~ ^[Yy]$ ]] && rm "$link"
                fi
            done < <(find "$home_subdir" -type l)
        fi
    done
}

# Symlink all files from a given files directory into $HOME
symlink_files() {
    local files_dir="$1"
    find "$files_dir" -type f -not -name ".keepme" | while read -r src; do
        rel="${src#$files_dir/}"
        dest="$HOME/$rel"
        mkdir -p "$(dirname "$dest")"
        ln -sf "$src" "$dest"
    done
}

# --- Symlinks ---
if should_run SYMLINKS; then
    log_section "Symlinks"
    log_action "Cleaning up broken symlinks..."
    if [ -d "$DOTFILES_DIR/shared/files" ]; then
        cleanup_broken_symlinks "$DOTFILES_DIR/shared/files"
    fi
    cleanup_broken_symlinks "$DOTFILES_DIR/files"

    log_action "Linking dotfiles into \$HOME..."
    if [ -d "$DOTFILES_DIR/shared/files" ]; then
        symlink_files "$DOTFILES_DIR/shared/files"
    fi
    symlink_files "$DOTFILES_DIR/files"

    # VS Code on macOS doesn't honor XDG; redirect its settings.json to ~/.config
    log_action "Linking VS Code settings.json to ~/.config..."
    VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
    mkdir -p "$VSCODE_USER_DIR"
    ln -sfn "$HOME/.config/Code/User/settings.json" "$VSCODE_USER_DIR/settings.json"

    log_info "Symlinks up to date"
fi

# --- Antidote ---
if should_run ANTIDOTE; then
    log_section "Antidote"
    if [ ! -d "$HOME/.antidote" ]; then
        log_action "Installing Antidote zsh plugin manager..."
        git clone --depth=1 https://github.com/mattmc3/antidote.git "${ZDOTDIR:-~}/.antidote"
        log_info "Antidote installed"
    else
        log_skip "Antidote already installed"
    fi
fi

# --- Homebrew packages ---
if should_run HOMEBREW; then
    log_action "Updating Homebrew..."
    brew update
    log_action "Upgrading all formulae and casks (--greedy)..."
    brew upgrade --greedy
    log_action "Running brew bundle (Brewfile)..."
    brew bundle --file=~/.Brewfile
    log_action "Running brew bundle (Brewfile.shared)..."
    brew bundle --file=~/.Brewfile.shared
    log_action "Cleaning up old versions..."
    brew cleanup
    log_info "Homebrew packages up to date"
fi

# --- Dotnet SDKs ---
if should_run DOTNET; then
    log_section "Dotnet SDKs"
    log_action "Registering side-by-side dotnet SDKs..."
    DOTNET_MAIN="/opt/homebrew/opt/dotnet/libexec"
    for versioned in /opt/homebrew/opt/dotnet@*/libexec; do
        [ "$versioned" = "$DOTNET_MAIN" ] && continue
        for sdk in "$versioned/sdk/"*/; do
            [ -d "$sdk" ] && ln -sfn "$sdk" "$DOTNET_MAIN/sdk/$(basename "$sdk")"
        done
        for host in "$versioned/host/fxr/"*/; do
            [ -d "$host" ] && ln -sfn "$host" "$DOTNET_MAIN/host/fxr/$(basename "$host")"
        done
        for shared in "$versioned/shared/"*/; do
            [ -d "$shared" ] || continue
            framework=$(basename "$shared")
            for ver in "$shared"*/; do
                [ -d "$ver" ] && mkdir -p "$DOTNET_MAIN/shared/$framework" && ln -sfn "$ver" "$DOTNET_MAIN/shared/$framework/$(basename "$ver")"
            done
        done
    done
    log_info "Dotnet SDKs registered"
fi

# --- macOS defaults (.osx) ---
if should_run MACOS; then
    log_action "Running .osx defaults script..."
    ~/.osx
    log_info "macOS defaults applied"
fi

# --- SSH config ---
if should_run SSH; then
    log_section "SSH Config"
    if ! sudo grep -q 'SetEnv PATH=' /etc/ssh/sshd_config; then
        log_action "Adding Homebrew PATH to sshd_config..."
        echo 'SetEnv PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin' | sudo tee -a /etc/ssh/sshd_config
        sudo launchctl kickstart -k system/com.openssh.sshd
        log_info "sshd_config updated and sshd restarted"
    else
        log_skip "sshd_config already configured"
    fi
fi

# --- Eternal Terminal ---
if should_run ET; then
    log_section "Eternal Terminal"
    log_action "Starting et service..."
    sudo brew services start et
    log_info "Eternal Terminal service started"
fi

# --- Claude Code ---
if should_run CLAUDE; then
    log_section "Claude Code"
    if ! command -v claude &> /dev/null; then
        log_action "Installing Claude Code..."
        curl -fsSL https://claude.ai/install.sh | bash
        log_info "Claude Code installed"
    else
        log_skip "Claude Code already installed"
    fi
fi

# --- iTerm2 AI plugin ---
if should_run ITERM; then
    log_section "iTerm2 AI Plugin"
    ITERM_AI_DIR="$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch/iTermAI"
    if [ ! -d "$ITERM_AI_DIR" ]; then
        log_action "Installing iTerm2 AI plugin..."
        curl -L -o /tmp/iTermAI.zip "https://github.com/gnachman/iterm2-website/raw/refs/heads/master/downloads/ai-plugin/iTermAI-1.1.zip"
        mkdir -p "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"
        unzip -qo /tmp/iTermAI.zip -d "$HOME/Library/Application Support/iTerm2/Scripts/AutoLaunch"
        rm /tmp/iTermAI.zip
        log_info "iTerm2 AI plugin installed"
    else
        log_skip "iTerm2 AI plugin already installed"
    fi
fi

# --- tmux plugins (TPM) ---
if should_run TMUX; then
    log_section "tmux plugins"
    TPM_DIR="$HOME/.tmux/plugins/tpm"
    if [ ! -d "$TPM_DIR" ]; then
        log_action "Cloning TPM..."
        git clone --depth=1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
        log_info "TPM installed"
    else
        log_skip "TPM already installed"
    fi
    log_action "Installing tmux plugins..."
    # install_plugins reads TMUX_PLUGIN_MANAGER_PATH from a running tmux server.
    # Start one if needed, and re-source the config to pick up TPM's env var.
    STARTED_TMUX=0
    if ! tmux ls >/dev/null 2>&1; then
        tmux new-session -d -s _bootstrap_tpm
        STARTED_TMUX=1
    fi
    tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 || true
    "$TPM_DIR/bin/install_plugins"
    [ "$STARTED_TMUX" -eq 1 ] && tmux kill-session -t _bootstrap_tpm >/dev/null 2>&1 || true
    log_info "tmux plugins up to date"
fi

printf "\n${BOLD}${GREEN}Bootstrap complete!${RESET}\n"
