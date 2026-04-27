alias reload='source ~/.zshrc'

if command -v eza &>/dev/null; then
  alias ls="eza --group-directories-first --color=auto"
  alias ll="eza -alh --git --octal-permissions --group-directories-first --color=auto"
  alias la="eza -A --group-directories-first --color=auto"
  alias l="eza -alh --git --group-directories-first --sort=changed --reverse --color=auto"
else
  if [[ "$OSTYPE" == "darwin"* ]]; then
    export LS_CMD="gls --color=auto"
  else
    export LS_CMD="ls --color=auto"
  fi
  alias ls="$LS_CMD"
  alias ll="$LS_CMD -alh"
  alias la="$LS_CMD -A"
  alias l="$LS_CMD -lahrtc"
fi

alias gs="git status"
alias gst="git status"
alias gadd="git add -A && git status -sb"
alias update_submodules="git pull --recurse-submodules && git submodule update"
alias grh_git_reset_hard="git reset --hard"
alias grhc_git_reset_hard_clean="git reset --hard && git clean -fd"
alias gprune="git fetch --prune"

# Syntax highlighting for less (-R for RAW ^ colors)
alias less='less -R'

alias path='echo $PATH'

# Verbosely show progress for move and copy
alias cp='cp -v'
alias mv='mv -v'

# Generate UUID and copy to clipboard
alias uuid="uuidgen | tr -d '\n' | tr '[:upper:]' '[:lower:]'  | pbcopy && pbpaste && echo"
alias flushdns="sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"

alias k="kubectl"

alias axon="clear && cd ~/workspace/evolution/axon/"
alias dotfiles="clear && cd ~/workspace/dotfiles/"
alias bootstrap="(cd ~/workspace/dotfiles && ./bootstrap.sh)"

alias build="docker compose build"
alias up="docker compose up"
alias upd="docker compose up -d"
alias down="docker compose down"
alias logs="docker compose logs -f"
