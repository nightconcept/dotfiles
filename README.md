# dotfiles
These are all my dotfiles that are meant to be interoporable between all machines that I use. I use Windows, macOS, and Linux often. This is intended to be used *after* `install-scripts`.

## Supported OS
- Arch Linux

## Requirements
- Git
- stow

## Linux Installation

First, check out the dotfiles repo in your $HOME directory using git

1. Download
```
$ git clone https://github.com/nightconcept/dotfiles.git
$ cd dotfiles
```
2. Install via stow to create symlinks in ~
```
stow .
```