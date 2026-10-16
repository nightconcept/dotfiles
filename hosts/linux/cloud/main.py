"""Cloud — Debian Docker host with a Windows Forgejo Actions runner.

Deploy the complete host with: just cloud
"""

from modules.linux.programs.docker import DockerModule
from modules.linux.programs.windows_runner.module import WindowsRunnerModule

DockerModule().deploy()
WindowsRunnerModule().deploy()
