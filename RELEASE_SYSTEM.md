# Crystal-Term Release System

A GitHub Actions-based release management system for the Crystal-Term monorepo that provides automated, centralized version control across all modules.

## Overview

The new release system replaces the complex Crystal-based release script with a simpler, more reliable approach:

1. **Root Version Control**: A single `shard.yml` at the repository root controls the version for all modules
2. **Bash Propagation Script**: A robust bash script propagates versions to all submodules
3. **GitHub Actions**: Automated release workflow triggered by changes to the root `shard.yml`
4. **Git Integration**: Proper handling of submodules, commits, and tags

## Architecture

```
crystal-term/
├── shard.yml                    # Master version file
├── scripts/
│   └── propagate-version.sh     # Version propagation script
├── .github/
│   └── workflows/
│       └── release.yml          # GitHub Actions workflow
├── color/                       # Individual modules
├── cursor/
├── prompt/
├── reader/
├── screen/
├── spinner/
└── terminfo/
```

## Components

### 1. Root shard.yml

The master configuration file that controls versions for all modules:

```yaml
name: crystal-term
version: 0.2.0  # This version propagates to all modules

authors:
  - Chris Watson <cawatson1993@gmail.com>

description: |
  A modular collection of Crystal libraries for building terminal/CLI applications.
  This is the monorepo root that manages versions for all crystal-term modules.

crystal: ">= 1.0.0"
license: MIT
```

### 2. Propagation Script

`scripts/propagate-version.sh` performs the following operations:

- **Reads** the version from the root `shard.yml`
- **Updates** each module's `shard.yml` version field
- **Updates** each module's `src/*/version.cr` VERSION constant  
- **Converts** inter-module dependencies from `branch: master` to `version: X.X.X`
- **Preserves** all other content (authors, dependencies, etc.)

**Key Features:**
- Uses `awk` for reliable text processing (more robust than `sed`)
- Creates temporary files for atomic updates
- Provides colored output and progress feedback
- Handles missing files gracefully

### 3. GitHub Actions Workflow

`.github/workflows/release.yml` provides automated release management:

**Triggers:**
- Push to `main` branch with changes to root `shard.yml`
- Manual workflow dispatch with optional force flag

**Process:**
1. **Detect Changes**: Compare current version with previous commit
2. **Propagate Versions**: Run the propagation script
3. **Commit Submodules**: Create individual commits in each submodule
4. **Create Tags**: Generate tags for each module (`term-color-v1.0.0`, etc.)
5. **Update Parent**: Commit submodule reference updates
6. **Push Everything**: Push all commits and tags to origin
7. **Create Releases**: Generate GitHub releases with comprehensive notes

## Usage

### Manual Release Process

1. **Update the root version**:
   ```bash
   # Edit shard.yml and change version
   version: 0.3.0
   ```

2. **Test the propagation locally** (optional):
   ```bash
   ./scripts/propagate-version.sh
   git diff  # Review changes
   ```

3. **Commit and push**:
   ```bash
   git add shard.yml
   git commit -m "Bump version to 0.3.0"
   git push origin main
   ```

4. **Monitor GitHub Actions**: The release workflow will automatically:
   - Propagate the version to all modules
   - Create commits and tags for each module
   - Push everything to GitHub
   - Create release notes

### Automated Release Process

The GitHub Actions workflow handles everything automatically when the root `shard.yml` version changes:

```yaml
# Workflow detects version change and:
- Propagates v0.3.0 to all 7 modules
- Creates 7 individual module commits
- Creates 8 tags (7 module + 1 parent)
- Pushes all changes
- Generates release notes
```

### Force Release

If you need to re-release the same version:

1. Go to **Actions** tab in GitHub
2. Select **Release Crystal-Term Modules** 
3. Click **Run workflow**
4. Check **Force release even if version unchanged**
5. Click **Run workflow**

## Module Tags

Each release creates individual tags for every module:

```bash
# Example for version 0.3.0
term-color-v0.3.0
term-cursor-v0.3.0
term-prompt-v0.3.0
term-reader-v0.3.0
term-screen-v0.3.0
term-spinner-v0.3.0
term-terminfo-v0.3.0
v0.3.0                # Parent repository tag
```

## Dependency Management

The system automatically manages inter-module dependencies:

**Before Release:**
```yaml
dependencies:
  term-cursor:
    github: crystal-term/cursor
    branch: master
```

**After Release:**
```yaml
dependencies:
  term-cursor:
    github: crystal-term/cursor
    version: 0.3.0
```

This ensures that released versions reference specific version tags rather than the moving `master` branch.

## Benefits

### Over the Previous System

1. **Reliability**: Bash/awk is more predictable than Crystal regex parsing
2. **Simplicity**: Single source of truth for versions
3. **Automation**: No manual intervention required
4. **Git Integration**: Proper submodule handling with GitHub Actions
5. **Visibility**: Clear release notes and GitHub releases
6. **Rollback**: Easy to revert version changes

### For Users

1. **Consistency**: All modules always have synchronized versions
2. **Stability**: Released versions pin exact dependency versions
3. **Discoverability**: Clear GitHub releases with comprehensive notes
4. **Individual Use**: Each module can still be used independently

## Troubleshooting

### Version Propagation Issues

If the propagation script fails:

1. **Check file permissions**:
   ```bash
   chmod +x scripts/propagate-version.sh
   ```

2. **Test locally**:
   ```bash
   ./scripts/propagate-version.sh
   ```

3. **Verify root shard.yml format**:
   ```bash
   awk '/^version:/ {print $2}' shard.yml
   ```

### GitHub Actions Issues

If the workflow fails:

1. **Check Actions tab** in GitHub repository
2. **Review workflow logs** for specific error messages
3. **Verify Git permissions** - workflow needs write access
4. **Check submodule status** - all submodules should be properly initialized

### Dependency Issues

If inter-module dependencies aren't updating:

1. **Verify shard.yml format** in affected modules
2. **Check that dependencies use exact format**:
   ```yaml
   term-cursor:
     github: crystal-term/cursor
     branch: master  # Will be converted to version: X.X.X
   ```

### Manual Recovery

If something goes wrong, you can manually fix issues:

```bash
# Revert changes
git reset --hard HEAD~1

# Or fix specific files
git checkout HEAD -- module/shard.yml

# Then re-run the propagation
./scripts/propagate-version.sh
```

## Migration Notes

### From the Old System

The old Crystal-based `release.cr` script had several issues:
- Complex regex parsing that could corrupt files
- Struct vs class bugs causing version loss
- Git submodule handling problems
- Difficult debugging and maintenance

### Key Differences

| Aspect | Old System | New System |
|--------|------------|------------|
| Language | Crystal | Bash + GitHub Actions |
| Version Control | Individual modules | Root shard.yml |
| Automation | Manual execution | GitHub Actions |
| Git Integration | Complex submodule logic | Native GitHub Actions |
| Debugging | Difficult | Clear logs and outputs |
| Reliability | Prone to file corruption | Atomic updates with awk |

## Future Enhancements

### Potential Improvements

1. **Release Notes**: Auto-generate from commit messages
2. **Changelog**: Maintain automated CHANGELOG.md files
3. **Testing**: Run tests before releasing
4. **Notifications**: Slack/Discord release notifications
5. **Metrics**: Track release frequency and adoption

### Configuration Options

The system could be extended with configuration options:

```yaml
# .github/release-config.yml
modules:
  - color
  - cursor
  # ... etc
  
notifications:
  slack_webhook: "https://..."
  
testing:
  run_before_release: true
  required_checks: ["specs", "lint"]
```

## Summary

The new GitHub Actions-based release system provides:

✅ **Centralized version control** through root `shard.yml`  
✅ **Reliable propagation** using bash/awk instead of complex Crystal code  
✅ **Full automation** via GitHub Actions workflows  
✅ **Proper git integration** with submodules, commits, and tags  
✅ **Clear visibility** through GitHub releases and comprehensive logging  
✅ **Easy maintenance** with simple, debuggable scripts  

This system eliminates the complexity and reliability issues of the previous Crystal-based approach while providing better automation and user experience.