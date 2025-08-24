# Crystal Language Documentation for Tektite

This directory contains comprehensive Crystal language documentation specifically curated for the Tektite MTProto implementation project. The documentation focuses on helping developers familiar with Ruby quickly become productive in Crystal.

## Contents

1. **[Language Fundamentals](01-language-fundamentals.md)** - Crystal syntax, semantics, and core concepts
2. **[Ruby to Crystal Migration](02-ruby-to-crystal.md)** - Key differences and migration guide for Ruby developers
3. **[Type System](03-type-system.md)** - Understanding Crystal's static type system
4. **[Concurrency Model](04-concurrency.md)** - Fibers, channels, and event-driven programming
5. **[Standard Library](05-standard-library.md)** - Common modules and classes
6. **[Performance and Memory](06-performance.md)** - Optimization techniques and memory management
7. **[Macros and Metaprogramming](07-macros.md)** - Compile-time code generation
8. **[Testing with Spectator](08-testing.md)** - Writing tests in Crystal
9. **[Best Practices](09-best-practices.md)** - Crystal idioms and patterns
10. **[Common Pitfalls](10-common-pitfalls.md)** - Gotchas when coming from Ruby

## Quick Start for Ruby Developers

If you're coming from Ruby, start with these key differences:

### Compilation

Crystal is compiled, not interpreted:

```bash
crystal build app.cr --release  # Compile with optimizations
./app                          # Run the binary
```

### Type System

Crystal has static typing with inference:

```crystal
# Type is inferred
name = "John"  # : String

# Explicit type annotation
age : Int32 = 25

# Union types
value : String | Int32 = rand < 0.5 ? "hello" : 42
```

### No Symbols as Values

Use enums instead of symbols:

```crystal
# Ruby way (NOT in Crystal)
# status = :active

# Crystal way
enum Status
  Active
  Inactive
end

status = Status::Active
```

### No Method Missing

Crystal doesn't have `method_missing`. Use macros for metaprogramming.

### Nil Handling

Crystal tracks nil at compile time:

```crystal
# This won't compile
name = nil
puts name.size  # Error: undefined method 'size' for Nil

# Use union types or nil checks
name : String? = nil
if name
  puts name.size  # OK, compiler knows name is not nil here
end
```

## Resources

- [Official Crystal Documentation](https://crystal-lang.org/reference/)
- [Crystal API Documentation](https://crystal-lang.org/api/)
- [Crystal Shards (packages)](https://shardbox.org/)
- [Crystal Forum](https://forum.crystal-lang.org/)

## Note on MTProto Implementation

When implementing MTProto in Crystal, pay special attention to:

- Binary data handling with `Slice(UInt8)` instead of Ruby's String
- Use `IO::Memory` for building binary protocols
- Crystal's `Bytes` alias for `Slice(UInt8)`
- Endianness handling with `IO::ByteFormat`
