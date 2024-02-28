########################
# Headers (do not touch)
########################

# Fig pre block. Keep at the top of this file.
[[ -f "$HOME/.fig/shell/zshrc.pre.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.pre.zsh"
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

###################
# Exports and evals
###################
export PATH="/home/danny/.local/share/fnm:$PATH"

export PATH="/usr/local/bin:$PATH"    # arm64e homebrew path (m1   )
export PATH="/opt/homebrew/bin:$PATH" # x86_64 homebrew path (intel)

export PATH="$PATH:/opt/nvim-linux64/bin"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

export LANG=en_US.UTF-8
export ZSH="$HOME/.oh-my-zsh"

export EDITOR=nvim
export VISUAL=nvim


eval "$(pyenv init -)"
eval "$(fnm env --use-on-cd)"
eval "$(zoxide init zsh)"
eval "$(thefuck --alias)"
if [ -d "$HOME/linuxbrew/" ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi


#########################
# oh-my-zsh configuration
#########################

# Path to your oh-my-zsh installation.

ZSH_THEME="powerlevel10k/powerlevel10k"

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# zsh plugins
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-history-substring-search
  zsh-completions
)

source $ZSH/oh-my-zsh.sh

#########
# Aliases
#########

# git aliases
alias gs='git status -sb'
alias gcm='git checkout master'
alias gaa='git add --all'
alias gc='git commit -m $2'
alias push='git push'
alias gpo='git push origin'
alias pull='git pull'
alias clone='git clone'
alias stash='git stash'
alias pop='git stash pop'
alias ga='git add'
alias gb='git branch'
alias gl="git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
alias gm='git merge'

# nvim aliases
alias vi='nvim'
alias vim='nvim'
export PATH="$PATH:/opt/nvim-linux64/bin"
alias e='$EDITOR'

# general aliases
alias .='z .'
alias ..='z ..'
alias ...='z ../../'
alias ....='z ../../../'
alias .....='z ../../../../'
alias cd='z'
alias cls='clear'
alias ls='eza -F --color=auto'
alias ll='eza -l'
alias ll.='eza -la'
alias lls='eza -la --sort=size'
alias llt='eza -la --sort=time'
alias cat='bat'
alias rm='rm -iv'
alias zshclear='echo "" > ~/.zsh_history'
alias zshconfig="vim ~/.zshrc"
alias zshreload="source ~/.zshrc"
alias mkdir="mkdir -p"
alias cp="cp -r"
alias apt="sudo apt"

########################
# Footers (do not touch)
########################

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f "$HOME/.config/powerlevel10k/.p10k.zsh" ]] || source "$HOME/.config/powerlevel10k/.p10k.zsh"

# Fig post block. Keep at the bottom of this file.
if [ -d "$HOME/.fig/" ]; then
  [[ -f "$HOME/.fig/shell/zshrc.post.zsh" ]] && builtin source "$HOME/.fig/shell/zshrc.post.zsh"
fi
