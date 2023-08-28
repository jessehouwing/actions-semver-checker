# Actions SemVer Checker Action

Every time you publish a new GitHub Action, say 1.2.3, it's customary to also update the tags for 1.2 and 1 to point to the same commit. That way people can subscribe to  either an exact version or a floating version that's automatically updated when the action's author pushes a new version.

Unfortunately, GitHub's creative use of tags doesn't do this automatically and many actions don't auto-update their major and minor versions whenever they release a new  patch.

An action author can run this action for their github actions repository to ensure the correct tags have been created and point to the correct commits.

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

# Future updates

I expect to update this action to automatically update the major and minor version when a new patch version is created.

And for it to generate the correct git commands to manually correct an existing action.