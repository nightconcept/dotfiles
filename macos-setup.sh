#!/usr/bin/env bash

sudo -v

# Install ohmyzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

defaults write .GlobalPreferences com.apple.mouse.scaling -1

# Install command-line tools using Homebrew.

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# Install system utils and tools
brew install git
brew install bat
brew install exa
brew install vim
brew install tldr
brew install gh

# Install pyenv to setup python
brew install pyenv
brew install openssl readline sqlite3 xz zlib

# see here: https://github.com/pyenv/pyenv/issues/2143#issuecomment-1069223994
brew install gcc
CC=/opt/homebrew/bin/gcc-11 pyenv install 3.8.12

# Install fnm (fast node modules), node LTS, and pnpm
brew install fnm
fnm install --lts
brew install pnpm

# Install terminal
brew install --cask hyper
brew install --cask fig

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