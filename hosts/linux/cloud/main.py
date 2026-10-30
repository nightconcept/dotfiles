"""Cloud — Debian Docker host with a Windows Forgejo Actions runner.

Deploy the complete host with: just cloud
"""

from modules.linux.programs.docker import DockerModule
from modules.linux.programs.windows_runner.module import WindowsRunnerModule
from modules.linux.services.unattended_upgrades import UnattendedUpgradesModule

UnattendedUpgradesModule().deploy()
DockerModule().deploy()
WindowsRunnerModule().deploy()
