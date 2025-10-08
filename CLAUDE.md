# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Crystal-term is a modular collection of Crystal libraries for building terminal/CLI applications. It consists of 8 independent but interrelated modules:

- **color** - Terminal color capabilities detection
- **cursor** - Terminal cursor movement and manipulation  
- **prompt** - Interactive command line prompts
- **reader** - Terminal input reading with line editing
- **rich** - Rich text formatting (early stage)
- **screen** - Terminal screen size detection
- **spinner** - Terminal spinners and progress indicators
- **terminfo** - Cross-platform terminal information (size, attributes) without ioctl dependency

Each module is a standalone Crystal shard that can be used independently or combined with others.

## Development Commands

### Local Development Setup

Root-managed monorepo: dependencies are defined in the root `shard.yml` using local paths.

```bash
# From the crystal-term root directory
shards install

# Run module specs from the root
crystal spec shards/cursor/spec
crystal spec shards/reader/spec

# Run an example from the root
crystal run shards/spinner/examples/basic.cr
```

### Working with Individual Modules

All development happens within individual module directories. Navigate to the specific module first:

```bash
cd shards/color/    # or shards/cursor/, shards/prompt/, shards/reader/, shards/screen/, shards/spinner/, shards/rich/, shards/terminfo/
```

### Core Commands

```bash
# Install dependencies (from module directory)
shards install

# Run all tests
crystal spec

# Run specific test file
crystal spec spec/unit/prompt_spec.cr

# Run tests with verbose output
crystal spec --verbose

# Format code
crystal tool format
crystal tool format src/ spec/

# Type check without building
crystal build --no-codegen src/term-color.cr

# Build and run examples
crystal run examples/spinner.cr
```

### Testing Patterns

- Uses Crystal's built-in spec framework
- Test files follow `*_spec.cr` naming convention
- Some modules (reader) also use Spectator for testing
- Run tests from within each module directory

## Architecture & Code Organization

### Module Structure

Each module follows this pattern:
```
module-name/
├── src/
│   ├── term-{module}.cr    # Main entry point
│   └── {module}/           # Implementation files
│       └── version.cr      # Version constant
├── spec/                   # Test files
├── examples/              # Usage examples (where applicable)
└── shard.yml              # Module configuration
```

### Key Architectural Patterns

1. **Module Pattern**: Each component uses `extend self` for singleton-like interfaces:
   ```crystal
   module Term
     module Cursor
       extend self
   ```

2. **Delegation Pattern**: Higher-level components delegate to lower-level ones:
   ```crystal
   delegate :clear_lines, :show, :hide, to: @cursor
   ```

3. **Platform Abstraction**: Uses Crystal's compile-time flags:
   ```crystal
   {% if flag?(:windows) %}
     # Windows-specific code
   {% else %}
     # Unix-specific code
   {% end %}
   ```

4. **Event-Based Input**: Reader module uses observer pattern for keyboard events

### Module Dependencies

```
cursor (standalone)
screen (standalone)
    ↓
reader (depends on cursor, screen)
    ↓
prompt (depends on reader, cursor, screen)
spinner (depends on cursor)
```

### Important Design Considerations

1. **ANSI Escape Sequences**: Cursor control uses standard ANSI/VT100 sequences
2. **Cross-Platform Support**: Abstract platform differences behind clean interfaces
3. **Environment Detection**: Multiple fallback strategies for terminal capabilities
4. **No Global State**: Each module instance maintains its own state
5. **Type Safety**: Leverage Crystal's type system - avoid dynamic typing

### Common Patterns

- Entry point files (e.g., `term-cursor.cr`) define the public API
- Internal implementation in subdirectories under module name
- Constants defined in separate files when extensive
- Platform-specific code isolated in dedicated files

## Crystal-Specific Guidelines

1. **Prefer Enums over Symbols**: Use enums for type safety instead of symbols
2. **No `.to_sym`**: This Ruby method doesn't exist in Crystal
3. **Compile-Time Macros**: Use `{% %}` for conditional compilation
4. **Type Annotations**: Add type annotations for public APIs
5. **Null Safety**: Use Crystal's nil-handling patterns (`try`, `not_nil!`)

## Working with Examples

Most modules include example scripts demonstrating usage:
```bash
# From module directory
crystal run examples/prompt.cr
crystal run examples/multi_spinner.cr
```

Study these examples to understand the intended API usage patterns.

## Module-Specific Notes

- **prompt**: Most complex module with multiple prompt types (ask, select, multi_select, etc.)
- **reader**: Low-level input handling, includes line editing capabilities  
- **screen**: Tries multiple detection methods (ioctl, readline, tput, stty, env)
- **spinner**: Supports both single and multi-spinner scenarios
- **color**: Environment-based detection of terminal color support
- **cursor**: Pure ANSI escape sequence generation
- **terminfo**: Cross-platform terminal info without ioctl, uses native Crystal + fallbacks

## Managing Dependencies

### Local Development

Each module’s `shard.yml` continues to reference GitHub URLs. For local development, the root `shard.yml` uses path dependencies to point at `./shards/<module>`. Always run builds/tests/examples from the repo root so Crystal picks up the root `shard.yml`.

### Testing Inter-Module Changes

When making changes that affect multiple modules:

1. Make your changes in the source module
2. Run `shards install` in dependent modules to pick up changes
3. Test thoroughly before committing

Example workflow:
```bash
# Make changes to cursor module
cd shards/cursor/
# ... edit files ...

# Test in reader module which depends on cursor
cd ../reader/
shards install  # Picks up local cursor changes
crystal spec    # Run tests
```