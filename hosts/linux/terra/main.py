from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.llama_cpp import LlamaCppModule
from modules.linux.programs.llm_models import LLMModelsModule
from modules.linux.programs.ssh import SSHModule
from modules.linux.programs.storage import StorageModule
from modules.linux.programs.docker import DockerModule
from modules.linux.programs.books.module import BooksModule
from modules.linux.programs.libbyrip_converter.module import LibbyRipConverterModule
from modules.linux.services.titan_mount import TitanMountModule

# Initialize modules
ssh = SSHModule()
storage = StorageModule()
titan = TitanMountModule()
docker = DockerModule()
books = BooksModule()
converter = LibbyRipConverterModule(app_port=8086)
hf = HuggingFaceModule()
llama = LlamaCppModule()
models = LLMModelsModule()

# Deploy system foundations
ssh.deploy()
storage.deploy()
titan.deploy()

# Deploy infrastructure
docker.deploy()

# Deploy services
books.deploy()
converter.deploy()

# Deploy AI modules
hf.deploy()
llama.deploy()
models.deploy()
