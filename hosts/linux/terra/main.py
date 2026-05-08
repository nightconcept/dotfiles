from modules.linux.programs.huggingface import HuggingFaceModule
from modules.linux.programs.llama_cpp import LlamaCppModule
from modules.linux.programs.llm_models import LLMModelsModule

# Initialize modules
hf = HuggingFaceModule()
llama = LlamaCppModule()
models = LLMModelsModule()

# Deploy modules
hf.deploy()
llama.deploy()
models.deploy()
