"""Deploy Terra's inference engines, model router, and Hermes agent together."""

from modules.linux.ai.alerts.module import HermesIocAlertModule
from modules.linux.ai.hermes import HermesModule
from modules.linux.ai.llama_cpp import LlamaCppModule
from modules.linux.ai.llama_swap import LlamaSwapModule
from modules.linux.ai.llm_models import LLMModelsModule
from modules.linux.ai.strata.module import StrataModule


class AIStackModule:
    """Own the deployment order of the inference and agent stack.

    Hugging Face CLI and Foreman are independent prerequisites managed by the host.
    Foreman's status remains the authority for whether the GPU is available.
    """

    def deploy(self):
        """Prepare models and engines before routing requests and updating Hermes."""
        LLMModelsModule().deploy()
        StrataModule().deploy()
        LlamaCppModule().deploy()
        LlamaSwapModule().deploy()
        HermesModule().deploy()
        HermesIocAlertModule().deploy()
