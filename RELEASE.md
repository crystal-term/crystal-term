# Crystal-Term Release Management

This document describes the release strategy and tools for managing releases across the crystal-term monorepo.

## Overview

Crystal-term is a monorepo containing 7 independent but interrelated Crystal modules:

- **term-color** - Terminal color capabilities detection
- **term-cursor** - Terminal cursor movement and manipulation  
- **term-prompt** - Interactive command line prompts
- **term-reader** - Terminal input reading with line editing
- **term-screen** - Terminal screen size detection
- **term-spinner** - Terminal spinners and progress indicators
- **term-terminfo** - Cross-platform terminal information without ioctl dependency

### Dependency Graph

```
cursor (standalone)
screen (standalone)
color (standalone)
terminfo (standalone)
    ↓
reader (depends on cursor, screen)
spinner (depends on cursor)
    ↓
prompt (depends on reader, cursor, screen)
```

## Release Tools

### 1. Interactive Release Manager (`release.cr`)

The main release tool that provides an interactive interface for managing releases across the entire monorepo.

```bash
# Run interactive release manager
crystal release.cr
```

**Features:**
- Dependency-aware version bumping
- Automatic inter-module dependency updates
- **Full git integration with safety checks**
- **Annotated git tag creation with proper commit messages**
- **Automatic push to origin with confirmation**
- **GitHub release URL generation**
- Support for major, minor, patch, and custom version bumps
- Repository validation before releases

**Release Types:**
- **Major** (x.0.0) - Breaking changes across all modules
- **Minor** (0.x.0) - New features, backward compatible
- **Patch** (0.0.x) - Bug fixes only
- **Custom** - Specify versions manually for each module

### 2. Individual Utility Scripts

#### Version Bump (`scripts/version-bump.cr`)

Update version for a single module:

```bash
# Bump specific version
crystal scripts/version-bump.cr cursor 1.2.3

# Bump by type
crystal scripts/version-bump.cr cursor major
crystal scripts/version-bump.cr cursor minor  
crystal scripts/version-bump.cr cursor patch
```

#### Dependency Update (`scripts/dependency-update.cr`)

Update inter-module dependency versions:

```bash
# Update specific dependency
crystal scripts/dependency-update.cr prompt term-cursor 1.2.0

# Update all dependencies to latest versions
crystal scripts/dependency-update.cr --all-latest
```

#### Version Validation (`scripts/validate-versions.cr`)

Validate version consistency across the monorepo:

```bash
# Validate all modules
crystal scripts/validate-versions.cr

# Show detailed information
crystal scripts/validate-versions.cr --detailed

# Automatically fix inconsistencies
crystal scripts/validate-versions.cr --fix
```

#### Git Release Utilities (`scripts/git-release.cr`)

Specialized git operations for releases:

```bash
# List all release tags with dates
crystal scripts/git-release.cr list-tags

# Check if a specific tag exists
crystal scripts/git-release.cr check-tag term-cursor-v1.0.0

# Create a release tag manually
crystal scripts/git-release.cr create-tag term-cursor 1.0.0

# Validate repository state for releases
crystal scripts/git-release.cr validate-repo

# Sync local tags with remote
crystal scripts/git-release.cr sync-tags

# Show release statistics and information
crystal scripts/git-release.cr release-info

# Delete a tag (use with extreme caution!)
crystal scripts/git-release.cr delete-tag term-cursor-v1.0.0
```

## Release Process

### Automated Release (Recommended)

For most releases, use the interactive release manager:

1. **Validate repository state:**
   ```bash
   # Check repository is ready for release
   crystal scripts/git-release.cr validate-repo
   
   # Validate version consistency
   crystal scripts/validate-versions.cr --detailed
   ```

2. **Run release manager:**
   ```bash
   crystal release.cr
   ```

3. **The release manager will automatically:**
   - **Validate git environment** (check for uncommitted changes, current branch)
   - **Show current versions** and dependency relationships
   - **Let you select release type** (major/minor/patch/custom)
   - **Preview all changes** before applying
   - **Update version files** in dependency order
   - **Create a single commit** with all version changes
   - **Generate annotated git tags** for each released module
   - **Offer to push to origin** immediately
   - **Show GitHub release URLs** if applicable

4. **Post-release verification:**
   ```bash
   # Verify tags were created
   crystal scripts/git-release.cr list-tags
   
   # Check latest releases
   crystal scripts/git-release.cr release-info
   ```

### Manual Release Process

For custom releases or when you need fine-grained control:

1. **Plan the release:**
   - Determine which modules need version updates
   - Consider dependency relationships
   - Plan the release order (dependencies first)

2. **Update versions:**
   ```bash
   # Update individual modules
   crystal scripts/version-bump.cr cursor 1.0.0
   crystal scripts/version-bump.cr screen 1.0.0
   ```

3. **Update inter-dependencies:**
   ```bash
   # Update dependencies to new versions
   crystal scripts/dependency-update.cr reader term-cursor 1.0.0
   crystal scripts/dependency-update.cr reader term-screen 1.0.0
   ```

4. **Validate changes:**
   ```bash
   crystal scripts/validate-versions.cr --detailed
   ```

5. **Test thoroughly:**
   ```bash
   ./dev-setup
   # Test each affected module
   cd cursor && crystal spec
   cd ../reader && crystal spec
   # etc...
   ```

6. **Create git commits and tags:**
   ```bash
   git add .
   git commit -m "Release cursor v1.0.0, screen v1.0.0, reader v1.0.0"
   
   # Create annotated tags for each module
   git tag -a term-cursor-v1.0.0 -m "Release term-cursor v1.0.0"
   git tag -a term-screen-v1.0.0 -m "Release term-screen v1.0.0"
   git tag -a term-reader-v1.0.0 -m "Release term-reader v1.0.0"
   
   # Push everything
   git push origin main --tags
   ```

**Or use the git utilities for individual operations:**
```bash
# Create tags individually
crystal scripts/git-release.cr create-tag term-cursor 1.0.0
crystal scripts/git-release.cr create-tag term-screen 1.0.0
crystal scripts/git-release.cr create-tag term-reader 1.0.0
```

## Version Management Strategy

### Semantic Versioning

All modules follow [Semantic Versioning](https://semver.org/):

- **MAJOR** - Breaking changes that require user code changes
- **MINOR** - New features that are backward compatible  
- **PATCH** - Bug fixes that don't change the API

### Coordinated Releases

Due to inter-module dependencies, releases are typically coordinated:

1. **Full Release** - All modules get the same version bump
2. **Selective Release** - Only affected modules and their dependents are updated
3. **Hotfix Release** - Patch versions for critical bug fixes

### Dependency Pinning

- Inter-module dependencies are pinned to specific versions (not branches)
- External dependencies can use version ranges
- Development uses local overrides via `shard.override.yml`

## Best Practices

### Before Release

1. **Validate repository and versions:**
   ```bash
   # Check git repository state
   crystal scripts/git-release.cr validate-repo
   
   # Validate version consistency
   crystal scripts/validate-versions.cr --detailed
   ```

2. **Test all affected modules:**
   ```bash
   # Set up local development environment
   ./dev-setup
   
   # Run tests for each module
   for dir in color cursor prompt reader screen spinner terminfo; do
     cd "$dir" && echo "Testing $dir..." && crystal spec
     cd ..
   done
   ```

3. **Check examples work:**
   ```bash
   cd prompt && crystal run examples/ask.cr
   cd ../spinner && crystal run examples/basic.cr
   ```

4. **Review git history:**
   ```bash
   # Check recent commits
   git log --oneline -10
   
   # Check current release tags
   crystal scripts/git-release.cr list-tags
   ```

### During Release

1. **Use the interactive tool** for most releases
2. **Review changes carefully** before confirming
3. **Test immediately after release** by installing from GitHub

### After Release

1. **Verify release was successful:**
   ```bash
   # Check tags were pushed
   crystal scripts/git-release.cr sync-tags
   
   # View release summary
   crystal scripts/git-release.cr release-info
   ```

2. **Test installation from GitHub:**
   ```bash
   # In a temporary directory
   crystal init test-install && cd test-install
   
   # Add dependency and test
   echo "dependencies:\n  term-cursor:\n    github: crystal-term/cursor\n    version: 1.0.0" >> shard.yml
   shards install && crystal eval "require \"term-cursor\"; puts Term::Cursor.move_to(10, 5)"
   ```

3. **Update documentation** if API changes were made
4. **Create GitHub releases** if using GitHub (the tool shows URLs)
5. **Announce the release** with changelog information
6. **Monitor for issues** and be prepared to create hotfix releases

## Troubleshooting

### Common Issues

**Version Mismatch:**
```bash
# Fix automatically
crystal scripts/validate-versions.cr --fix
```

**Missing Version Files:**
```bash
# prompt module was missing version.cr (now fixed)
# Check if any other modules need version files
find . -name "shard.yml" -exec dirname {} \; | while read dir; do
  module_name=$(basename "$dir")
  version_file="$dir/src/$module_name/version.cr"
  [ ! -f "$version_file" ] && echo "Missing: $version_file"
done
```

**Dependency Issues:**
```bash
# Update all to latest local versions
crystal scripts/dependency-update.cr --all-latest
```

**Build Issues After Release:**
```bash
# Clean and reinstall dependencies
rm -rf lib shard.lock
shards install
crystal spec
```

### Git Issues

**Tags not pushed:**
```bash
# Check what tags exist locally vs remotely
crystal scripts/git-release.cr sync-tags

# Push specific tags
git push origin term-cursor-v1.0.0

# Or push all tags
git push origin --tags
```

**Wrong tag created:**
```bash
# Delete tag locally and remotely (DANGEROUS!)
crystal scripts/git-release.cr delete-tag term-cursor-v1.0.0

# Recreate with correct information
crystal scripts/git-release.cr create-tag term-cursor 1.0.0
```

**Repository not ready for release:**
```bash
# Check what's wrong
crystal scripts/git-release.cr validate-repo

# Common fixes:
git add . && git commit -m "Prepare for release"  # Commit changes
git checkout main                                  # Switch to main branch
git pull origin main                               # Sync with remote
```

### Emergency Rollback

If a release has issues:

1. **Identify the problematic version**
2. **Delete problematic tags if not yet widely used:**
   ```bash
   crystal scripts/git-release.cr delete-tag term-module-v1.0.0
   ```
3. **Create hotfix branch from previous version:**
   ```bash
   git checkout -b hotfix/v1.0.1 term-module-v0.9.0
   ```
4. **Fix the issue and create patch release**
5. **Update dependents if necessary**

## Development Workflow Integration

### Local Development

```bash
# Set up local path overrides
./dev-setup

# Work on individual modules
cd prompt
crystal spec
crystal run examples/ask.cr

# Dependencies will use local versions automatically
```

### CI/CD Integration

The release tools are designed to work with automated CI/CD:

```bash
# In CI pipeline:
crystal scripts/validate-versions.cr
# Run all tests
# If releasing: crystal release.cr with non-interactive mode (future enhancement)
```

## Future Enhancements

Planned improvements to the release system:

1. **Non-interactive mode** for CI/CD integration
2. **Changelog generation** from git commits
3. **Release notes automation** with breaking change detection
4. **Pre-release validation** including build tests
5. **Integration with GitHub Releases** API

---

For questions or issues with the release process, please open an issue in the crystal-term repository.