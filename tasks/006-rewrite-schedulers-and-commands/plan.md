# Plan

1. Extract the minimal common scheduler responsibilities.
2. Rewrite command entry points without changing their names or models.
3. Rewrite or merge scheduler skills around public CLI operations.
4. Replace prose-contract tests with observable scheduling tests where
   practical.
5. Run deterministic command scenarios and `bin/check`.
