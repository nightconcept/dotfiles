# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

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
plugins=(git)

source $ZSH/oh-my-zsh.sh

# User configuration

# git config
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

# nvim config
alias vi='nvim'
alias vim='nvim'
export PATH="$PATH:/opt/nvim-linux64/bin"

# zsh config
alias .='cd .'
alias ..='cd ..'
alias ...='cd ../../'
alias ....='cd ../../../'
alias .....='cd ../../../../'

# General Aliases
alias .='z .'
alias ..='z ..'
alias ...='z ../../'
alias ....='z ../../../'
alias .....='z ../../../../'
alias cd='z'
alias cls='clear'
alias ls='exa -F --color=auto'
alias ll='exa -l'
alias ll.='exa -la'
alias lls='exa -la --sort=size'
alias llt='exa -la --sort=time'
alias rm='rm -iv'
alias zshclear='echo "" > ~/.zsh_history'
alias zshconfig="vim ~/.zshrc"
alias zshreload="source ~/.zshrc"

# fnm config
export PATH="/home/danny/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd)"

export PATH="/usr/local/bin:$PATH"    # arm64e homebrew path (m1   )
export PATH="/opt/homebrew/bin:$PATH" # x86_64 homebrew path (intel)

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases

# alias ohmyzsh="mate ~/.oh-my-zsh"

eval "$(zoxide init zsh)"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
