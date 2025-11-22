# CI/CD Quick Reference Guide

## For Developers

### Creating a New Release

1. **Update version in `pubspec.yaml`**
   ```yaml
   version: 1.2.3+1  # Update this line
   ```

2. **Commit your changes**
   ```bash
   git add pubspec.yaml
   git commit -m "Bump version to 1.2.3"
   git push origin main
   ```

3. **Create and push a version tag**
   ```bash
   git tag -a v1.2.3 -m "Release version 1.2.3"
   git push origin v1.2.3
   ```

4. **Wait for automation**
   - GitHub Actions will automatically build APK and AAB
   - A new release will be created with artifacts attached
   - Check the Actions tab for progress

### Checking Build Status

- Visit: `https://github.com/anima-regem/empty-player/actions`
- Look for your branch or PR name
- Click on the workflow run to see details
- Failed builds will show red X, successful ones show green checkmark

### Downloading Build Artifacts

**From Pull Requests:**
1. Go to the PR's "Checks" tab
2. Click on the workflow run
3. Scroll to "Artifacts" section
4. Download the APK

**From Releases:**
1. Go to: `https://github.com/anima-regem/empty-player/releases`
2. Find your version
3. Download APK or AAB from assets

### Workflow Files

- **`.github/workflows/build.yml`** - Runs on push/PR to main/develop
- **`.github/workflows/release.yml`** - Runs when version tag is pushed
- **`.github/workflows/pr-checks.yml`** - Stricter checks for pull requests

### Common Issues

**Build fails with "command not found"**
- The workflow will install Flutter automatically
- Local development still requires Flutter installation

**Release not created after pushing tag**
- Ensure tag format is `v*.*.*` (e.g., v1.0.0, not 1.0.0)
- Check Actions tab for error messages
- Verify you have push permissions

**Tests failing in CI but passing locally**
- Run `flutter clean && flutter pub get` locally
- Check for environment-specific issues
- Review the workflow logs for details

### Version Numbering

Follow Semantic Versioning:
- `v1.0.0` - Major version (breaking changes)
- `v1.1.0` - Minor version (new features)
- `v1.0.1` - Patch version (bug fixes)

The `+1` in `pubspec.yaml` is the build number, increment it for each build.

### Best Practices

1. **Always create PRs to develop first**
   - Let the build workflow validate your changes
   - Merge to main only when ready for release

2. **Test locally before pushing**
   ```bash
   flutter analyze
   flutter test
   flutter build apk
   ```

3. **Keep commits atomic**
   - One feature/fix per commit
   - Makes it easier to generate release notes

4. **Update CHANGELOG** (if you create one)
   - Document what changed in each version
   - Makes release notes more meaningful

### Monitoring

- **Build times**: Usually 5-10 minutes
- **Release times**: Usually 10-15 minutes
- **Artifact retention**: 30 days for build artifacts

### Getting Help

- Check the [Release Campaign Plan](RELEASE_CAMPAIGN_PLAN.md) for detailed info
- Review workflow logs in the Actions tab
- Check GitHub Actions documentation: https://docs.github.com/actions

---

**Quick Links:**
- [Actions](https://github.com/anima-regem/empty-player/actions)
- [Releases](https://github.com/anima-regem/empty-player/releases)
- [Release Campaign Plan](RELEASE_CAMPAIGN_PLAN.md)
