#!/bin/bash

# macOS bootstrapping to be run before running install.sh
# pulled from https://github.com/atomantic/dotfiles/blob/main/install.sh

# include my library helpers for colorized echo
source ./lib/echoes.sh

# ###########################################################
# Install non-brew various tools (PRE-BREW Installs)
# ###########################################################

bot "Ensuring build/install tools are available"
if ! xcode-select --print-path &> /dev/null; then

    # Prompt user to install the XCode Command Line Tools
    xcode-select --install &> /dev/null

    # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

    # Wait until the XCode Command Line Tools are installed
    until xcode-select --print-path &> /dev/null; do
        sleep 5
    done

    print_result $? ' XCode Command Line Tools Installed'

    # Prompt user to agree to the terms of the Xcode license
    # https://github.com/alrra/dotfiles/issues/10

    sudo xcodebuild -license
    print_result $? 'Agree with the XCode Command Line Tools licence'

fi

# ###########################################################
# install homebrew (CLI Packages)
# ###########################################################
running "Checking homebrew..."
brew_bin=$(which brew) 2>&1 > /dev/null
if [[ $? != 0 ]]; then
  action "Installing homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ $? != 0 ]]; then
    error "Unable to install homebrew, script $0 abort!"
    exit 2
  fi
  (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> /Users/${whoami}/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  brew analytics off
else
  ok
  bot "Homebrew"
  read -r -p "run brew update && upgrade? [y|N] " response
  if [[ $response =~ (y|yes|Y) ]]; then
    action "updating homebrew..."
    brew update
    ok "homebrew updated"
    action "upgrading brew packages..."
    brew upgrade
    ok "brews upgraded"
  else
    ok "skipped brew package upgrades."
  fi
fi

# Just to avoid a potential bug
brew doctor
mkdir -p ~/Library/Caches/Homebrew/Formula

# ###########################################################
# install python via pyenv
# ###########################################################
# Libraries required to run pyenv as found and suggested
# https://stackoverflow.com/questions/70152525/cannot-install-python-3-10-0-on-m1-apple-silicon-ld-symbols-not-found-for-a
# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
brew install openssl readline sqlite3 xz zlib tcl-tk gettext
brew install pyenv

# Note: Python 3.11.5 was the last tested version and was able to compile with no errors on 2/17/24.
pyenv install 3.11.5