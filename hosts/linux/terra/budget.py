"""Deploy only the Actual Budget and Paisa stack on Terra."""

from modules.linux.programs.budget.module import BudgetModule

budget = BudgetModule()
budget.deploy()
