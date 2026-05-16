from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.llama_cpp import LlamaCppModule
from modules.linux.programs.llm_models import LLMModelsModule
from modules.linux.programs.ssh import SSHModule
from modules.linux.programs.storage import StorageModule
from modules.linux.programs.docker import DockerModule
from modules.linux.programs.books.module import BooksModule

# Initialize modules
ssh = SSHModule()
storage = StorageModule()
docker = DockerModule()
books = BooksModule()
hf = HuggingFaceModule()
llama = LlamaCppModule()
models = LLMModelsModule()

# Deploy system foundations
ssh.deploy()
storage.deploy()

# Deploy infrastructure
docker.deploy()

# Deploy services
books.deploy()

# Deploy AI modules
hf.deploy()
llama.deploy()
models.deploy()
