# How to Release a New Version

To release a new version, follow these steps after creating a PR with your changes:

## 1. Update the Changeset File

In your branch, run the following command to create a new changeset file:

```bash
npm run cs
```

You will be prompted to specify the type of changes you are making. Choose from the following options:
- `patch`: bug fixes, documentation updates, etc.
- `minor`: new features, non-breaking changes, etc.
- `major`: breaking changes, etc.

Next, you will be prompted to enter a summary of the changes you made. This will be used to generate the release notes in the `CHANGELOG.md` file.

## 2. Commit the Changeset File

```bash
git add .
git commit -m "chore: update changeset"
git push
```

## 3. Merge the PR

Once the PR is merged into the main branch, a release PR will be automatically created. This PR will:
  - Update the `CHANGELOG.md` file with the changes made in the release.
  - Bump the version number of the package.

## 4. Merge the Release PR

When the release PR is ready, merge it. This action will trigger the [publish workflow](../.github/workflows/publish-to-npm.yaml) to publish the package to NPM
