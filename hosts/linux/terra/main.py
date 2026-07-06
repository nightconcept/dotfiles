from modules.linux.programs.home_manager import HomeManagerModule
from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.llama_cpp import LlamaCppModule
from modules.linux.programs.llama_swap import LlamaSwapModule
from modules.linux.programs.llm_models import LLMModelsModule
from modules.linux.programs.ssh import SSHModule
from modules.linux.programs.storage import StorageModule
from modules.linux.programs.docker import DockerModule
from modules.linux.programs.books.module import BooksModule
from modules.linux.programs.libbyrip_converter.module import LibbyRipConverterModule
from modules.linux.services.titan_mount import TitanMountModule

# Initialize modules
ssh = SSHModule()
home_manager = HomeManagerModule(profile="desktop")
storage = StorageModule()
titan = TitanMountModule()
docker = DockerModule()
books = BooksModule()
converter = LibbyRipConverterModule(app_port=8086)
hf = HuggingFaceModule()
llama = LlamaCppModule()
llama_swap = LlamaSwapModule()
models = LLMModelsModule()

# Deploy system foundations
ssh.deploy()
home_manager.deploy()
storage.deploy()
titan.deploy()

# Deploy infrastructure
docker.deploy()

# Deploy services
books.deploy()
converter.deploy()

# Deploy AI modules
hf.deploy()
models.deploy()
llama.deploy()
llama_swap.deploy()
