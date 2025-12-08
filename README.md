# Actions SemVer Checker Action

Every time you publish a new version of a GitHub Action, say `v1.2.3`, it's customary to also update the tags for `v1.2` and `v1` to point to the same commit. That way people can subscribe to  either an exact version or a floating version that's automatically updated when the action's author pushes a new version.

Unfortunately, GitHub's creative use of tags doesn't do this automatically and many actions don't auto-update their major and minor versions whenever they release a new  patch.

You can run this action for your GitHub Action's repository to ensure the correct tags have been created and point to the correct commits.

Example output:

> ### Annotations
>
> 🔴 Incorrect version
> ```
> Version: v1 ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```
> 
> 🔴 Incorrect version
> ```
> Version: v1.0 ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```
> 🔴 Incorrect version
> ```
> Version: latest ref 59499a44cd4482b68a7e989a5e7dd781414facfa must match: v1.0.6 ref 1a13fd188ebef96fb179faedfabcc8de5cb6189d
> ```

And a set of suggested Git commands to fix this:

> ### Suggested fix:
> ```
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:refs/tags/v1 --force
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:refs/tags/v1.0 --force
> git push origin 1a13fd188ebef96fb179faedfabcc8de5cb6189d:latest --force
> ```

# Usage

```yaml  
- uses: actions/checkout@v4
  # Check out with fetch-depth: 0
  with:
    fetch-depth: 0

- uses: jessehouwing/actions-semver-checker@v1
  with:
    # Configures warnings for minor versions.
    # Default: true
    check-minor-version: ''
```

[Example workflow](https://github.com/jessehouwing/actions-semver-checker/blob/main/.github/workflows/action-semver-checker.yml):

```yaml
name: Check SemVer

on:
  push:
    tags:
      - '*'
  workflow_dispatch:

jobs:
  check-semver:
    concurrency:
      group: '${{ github.workflow }}'
      cancel-in-progress: true
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - uses: jessehouwing/actions-semver-checker@v1
        with:
          check-minor-version: true
```
# Future updates

I expect to update this action to

 * automatically update the major and minor version when a new patch version is created.
 * ensure proper github releases exist for each tag
 * ensure github release tags are signed
 * drop a sarif file so the task can generate security issues.
