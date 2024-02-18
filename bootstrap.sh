#!/bin/bash

xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew update
brew install openssl readline sqlite3 xz zlib tcl-tk gettext
brew install pyenv
pyenv install 3.11.5