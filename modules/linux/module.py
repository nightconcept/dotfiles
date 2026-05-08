"""Base class for host configuration modules."""

from abc import ABC, abstractmethod


class HostModule(ABC):
    """Base class for host configuration modules."""

    @abstractmethod
    def install(self):
        """Install the module's components if not present."""
        pass

    @abstractmethod
    def update(self):
        """Update the module's components to the latest version."""
        pass

    def cleanup(self):
        """Remove orphan or obsolete artifacts. Optional."""
        pass

    def service(self):
        """Configure and enable persistent system service(s). Optional."""
        pass

    @abstractmethod
    def remove(self):
        """Remove the module's components."""
        pass

    def deploy(self):
        """Standard deployment flow: install, update, service, and cleanup."""
        self.install()
        self.update()
        self.service()
        self.cleanup()
