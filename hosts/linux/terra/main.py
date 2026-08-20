from modules.linux.programs.books.module import BooksModule
from modules.linux.programs.docker import DockerModule
from modules.linux.programs.foreign_arch import ForeignArchModule
from modules.linux.programs.hermes import HermesModule
from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.libbyrip_converter.module import LibbyRipConverterModule
from modules.linux.programs.llama_cpp import LlamaCppModule
from modules.linux.programs.llama_swap import LlamaSwapModule
from modules.linux.programs.llm_models import LLMModelsModule
from modules.linux.programs.paseo.module import PaseoModule
from modules.linux.programs.ssh import SSHModule
from modules.linux.programs.storage import StorageModule
from modules.linux.programs.watchtower.module import WatchtowerModule
from modules.linux.services.titan_mount import TitanMountModule

# Initialize modules
ssh = SSHModule()
home_manager = HomeManagerModule(profile="desktop")
foreign_arch = ForeignArchModule(arch="aarch64-linux")
storage = StorageModule()
titan = TitanMountModule()
docker = DockerModule()
books = BooksModule()
converter = LibbyRipConverterModule(app_port=8086)
paseo = PaseoModule(port=6767)
watchtower = WatchtowerModule()
hf = HuggingFaceModule()
llama = LlamaCppModule()
llama_swap = LlamaSwapModule()
models = LLMModelsModule()
hermes = HermesModule()

# Deploy system foundations
ssh.deploy()
home_manager.install()
foreign_arch.deploy()
home_manager.update()
storage.deploy()
titan.deploy()

# Deploy infrastructure
docker.deploy()

# Deploy services
books.deploy()
converter.deploy()
paseo.deploy()
watchtower.deploy()

# Deploy AI modules
hf.deploy()
models.deploy()
llama.deploy()
llama_swap.deploy()
hermes.deploy()

