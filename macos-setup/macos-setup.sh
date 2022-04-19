#!/usr/bin/env bash

sudo -v

# Mac settings
defaults write .GlobalPreferences com.apple.mouse.scaling -1

# Install ohmyzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install brew
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# instal gcc
brew install gcc

# Install system utils and tools
brew install git
brew install bat
brew install exa
brew install vim
brew install tldr
brew install gh
brew install thefuck
fuck
fuck

# Install pyenv to setup python, this works on Mac
brew install pyenv
brew install openssl readline sqlite3 xz zlib

# see here: https://github.com/pyenv/pyenv/issues/2143#issuecomment-1069223994
CC=/opt/homebrew/bin/gcc-11 pyenv install 3.8.12

# Install fnm (fast node modules), node LTS, and pnpm
brew install fnm
fnm install --lts
brew install pnpm

# Install terminal tools
brew install --cask hyper
brew install --cask fig

# setup terminal plugins
git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/spaceship-prompt/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"
pnpm i -g hyperterm-atom-dark

# Install web development tools
brew install --cask vscodium
brew install --cask firefox-developer-edition
brew install --cask eloston-chromium
brew install --cask runjs

# Install everything else
brew install --cask discord
brew install --cask rocket
brew install --cask stretchly
brew install --cask dozer
brew install --cask obsidian
brew install --cask spotify
brew install --cask plex
brew install --cask google-drive
brew install --cask bettertouchtool
brew install --cask raycast
brew install --cask mos

# Remove outdated versions from the cellar.
brew cleanup