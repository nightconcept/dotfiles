#!/bin/bash

set -e

source lib/common.sh

DISTRO=get_distro()

# Install Ansible
if [ "$DISTRO" == "Ubuntu"* ]; then
	sudo apt-add-repository -y ppa:ansible/ansible
	sudo apt update
	sudo apt -y install ansible
	export PATH="$PATH:~/.local/bin"
elif [[ "$DISTRO" == "arch os" || "$DISTRO" == "ManjaroLinux" ]]; then
	python3 -m venv venv
	source venv/bin/activate
	pip3 install ansible
	export PATH="$PATH:~/.local/bin"
elif ["$DISTRO" == "EndeavourOS" ]; then
	python3 -m venv venv
	source venv/bin/activate
	pip3 install ansible
	export PATH="$PATH:~/.local/bin"
elif [ "$DISTRO" == "darwin" ]; then
	python3 -m venv venv
	source venv/bin/activate
	pip3 install ansible
fi

ansible-galaxy install -r requirements.yml
if [ "$1" == "server" ]; then
    ansible-playbook main.yml --ask-become-pass --tags server
else
    ansible-playbook main.yml --ask-become-pass
fi