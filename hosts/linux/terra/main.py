from modules.linux.ai.module import AIStackModule
from modules.linux.programs.books.module import BooksModule
from modules.linux.programs.colab import ColabModule
from modules.linux.programs.docker import DockerModule
from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.koreader_sync.module import KoreaderSyncModule
from modules.linux.programs.paseo.module import PaseoModule
from modules.linux.programs.pinchflat.module import PinchflatModule
from modules.linux.programs.ssh import SSHModule
from modules.linux.programs.storage import StorageModule
from modules.linux.programs.watchtower.module import WatchtowerModule
from modules.linux.services.tailscale import TailscaleModule
from modules.linux.services.titan_mount import TitanMountModule
from modules.linux.services.wifi_power_save import WiFiPowerSaveModule
from modules.linux.services.wifi_watchdog import WiFiWatchdogModule

# Initialize modules
ssh = SSHModule()
home_manager = HomeManagerModule(profile="desktop")
storage = StorageModule()
titan = TitanMountModule()
tailscale = TailscaleModule()
wifi_power_save = WiFiPowerSaveModule()
wifi_watchdog = WiFiWatchdogModule()
docker = DockerModule()
books = BooksModule()
kosync = KoreaderSyncModule()
paseo = PaseoModule(port=6767)
pinchflat = PinchflatModule()
watchtower = WatchtowerModule()
hf = HuggingFaceModule()
colab = ColabModule()
ai = AIStackModule()

# Deploy system foundations
ssh.deploy()
home_manager.install()
home_manager.update()
storage.deploy()
titan.deploy()
tailscale.deploy()
wifi_power_save.deploy()
wifi_watchdog.deploy()

# Deploy infrastructure
docker.deploy()

# Deploy services
books.deploy()
kosync.deploy()
paseo.deploy()
pinchflat.deploy()
watchtower.deploy()

# Deploy independent AI tooling, then the inference and agent stack.
hf.deploy()
colab.deploy()
ai.deploy()
