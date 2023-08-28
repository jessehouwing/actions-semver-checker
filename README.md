# Actions SemVer Checker Action

Run this action for your github actions repository to ensure the correct tags have been created aed point to the correct commits.

# Usage

```yaml
      # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0

      # Runs a single command using the runners shell
      - uses: jessehouwing/actions-semver-checker@v1
```
