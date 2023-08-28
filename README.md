# Actions SemVer Checker Action

Run this action for your github actions repository to ensure the correct tags have been created and point to the correct commits.

Example output:

```
WARNING: Ambigouous version: v1 - Exists as both tag (f43a0e5ff2bd294095638e18286ca9a3d1956744) and branch (f43a0e5ff2bd294095638e18286ca9a3d1956744)
ERROR: Version: v1.0.0 does not exist and must match: v1 ref f43a0e5ff2bd294095638e18286ca9a3d1956744
```

# Usage

```yaml
      
      - uses: actions/checkout@v3
        # Check out with fetch-depth: 0
        with:
          fetch-depth: 0

      - uses: jessehouwing/actions-semver-checker@v1
```
