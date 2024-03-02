#!/usr/bin/env bash

# Save current working directory
cwd=$(pwd)

# Stow most dotfiles
cd ~/dotfiles
stow .

# Stow zshrc files because they are weird
cd ~/dotfiles/.config/
stow zsh -t ~

# Return to current working directory
cd $cwd