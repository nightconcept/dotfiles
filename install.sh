#!/bin/bash

parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

# Check for zsh
if [[ `which zsh &>/dev/null && $?` != 0 ]]
then
  echo "ZSH is not installed! Install it and try again."
fi

# Install oh-my-zsh
if [ -d ~/.oh-my-zsh ]; then
	echo "oh-my-zsh is installed"
else
 	echo "Installing oh-my-zsh"
  curl -L https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh | sh
fi

# Make the symlinks
Links=(
  .tmux.conf
  .vimrc
  .zlogin
  .zprofile
  .shell
  .wezterm
)
for i in "${Links[@]}"
do
  if [ -h $i ]; then
    echo "$i is configured"
  else
    echo "Linking $i"
    ln -s $PWD/$i ~/$i
  fi
done