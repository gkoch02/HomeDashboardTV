# Branch rulesets

`main.json` is the protection applied to `main`, modelled on HomeDashboard's:

- `main` can't be deleted or force-pushed.
- Changes go through a pull request, with no approval needed. Review threads must be resolved before merging.
- The `core` CI job must pass on a branch that is up to date with `main`.

GitHub doesn't read this file. After editing it, push the change yourself:

```bash
RULESET_ID=$(gh api /repos/gkoch02/HomeDashboardTV/rulesets --jq '.[] | select(.name=="main branch protection") | .id')
gh api --method PUT "/repos/gkoch02/HomeDashboardTV/rulesets/$RULESET_ID" --input .github/rulesets/main.json
```

If you add a CI job, add it to `required_status_checks` too. A required check must report on every PR, so CI has no paths filter.
