# How to Release a New Version

## Release Official Versions

To release a new version, follow these steps after creating a PR with your changes:

### 1. Update the Changeset File

In your branch, run the following command to create a new changeset file:

```bash
npm run cs
```

You will be prompted to specify the type of changes you are making. Choose from the following options:

-   `patch`: bug fixes, documentation updates, etc.
-   `minor`: new features, non-breaking changes, etc.
-   `major`: breaking changes, etc.

Next, you will be prompted to enter a summary of the changes you made. This will be used to generate the release notes in the `CHANGELOG.md` file.

### 2. Commit the Changeset File

```bash
git add .
git commit -m "chore: update changeset"
git push
```

### 3. Trigger the Release Workflow

Trigger the release workflow [here](https://github.com/axelarnetwork/axelar-cgp-sui/actions/workflows/release.yaml) when you want to publish the package. The release PR will be created. This PR will:

-   Update the `CHANGELOG.md` file with the changes made in the release.
-   Bump the version number of the package.
-   Publish the package to NPM.
-   Create a new GitHub release.

## Release Snapshot Versions

If you need to release a snapshot version for development or testing purposes, you can do so by triggering the snapshot release workflow [here](https://github.com/axelarnetwork/axelar-cgp-sui/actions/workflows/release-snapshot.yaml)
