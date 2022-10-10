#!/usr/bin/env bash

sudo -v

# Update Linux
sudo apt-get update
sudo apt-get upgrade
sudo apt-get -y install

# Install zsh
sudo apt-get -y install zsh

# Install ohmyzsh
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Install brew
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install command-line tools using Homebrew.
sudo apt-get -y install build-essential

# add brew to path
# to .profile doesn't work?
#echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/danny/.profile
#eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# this makes it work with zsh
test -r ~/.zshrc && echo "eval \$($(brew --prefix)/bin/brew shellenv)" >>~/.zshrc

# Make sure we’re using the latest Homebrew.
brew update

# Upgrade any already-installed formulae.
brew upgrade

# instal gcc
brew install gcc

# Install system utils and tools
brew install git
brew install bat
brew install gh
brew install exa
brew install vim
brew install thefuck
fuck
fuck
brew install tldr

# setup terminal plugins
git clone https://github.com/agkozak/zsh-z $ZSH_CUSTOM/plugins/zsh-z
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/spaceship-prompt/spaceship-prompt.git "$ZSH_CUSTOM/themes/spaceship-prompt" --depth=1
ln -s "$ZSH_CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" "$ZSH_CUSTOM/themes/spaceship.zsh-theme"

# Server specific installation
brew install --cask vscodium
apt-get install openssh-server
systemctl enable ssh --now
ufw allow ssh
ufw enable
ufw status
curl -sSL https://install.pi-hole.net | bash
apt install unbound
apt install samba
apt install ddclient

# Remove outdated versions from the cellar.
brew cleanup