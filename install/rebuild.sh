#!/bin/bash
####
# script that re-runs the playbook so you don't need
# to remember the ansible playbook command
# intended to mirror nixos-rebuild switch
####

set -e

if [ "$1" == "server" ]; then
    ansible-playbook main.yml --ask-become-pass --tags server
else
    ansible-playbook main.yml --ask-become-pass
fi