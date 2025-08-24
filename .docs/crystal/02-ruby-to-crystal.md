# Ruby to Crystal Migration Guide

This guide highlights the key differences between Ruby and Crystal to help Ruby developers quickly adapt to Crystal.

## Key Philosophical Differences

### Crystal is Compiled

- Crystal compiles to native machine code
- No interpreter, no REPL (though there's ICR - Interactive Crystal)
- Compile-time errors instead of runtime errors
- Much faster execution but requires compilation step

### Static Typing with Inference

- Types are determined at compile time
- You often don't need to specify types (inference)
- Type errors caught before runtime
- No duck typing in the Ruby sense

### No Runtime Metaprogramming

- No `method_missing`, `define_method`, or `eval`
- Use macros for compile-time metaprogramming
- All methods must be known at compile time

## Syntax Differences

### Symbols Are Not Objects

```ruby
# Ruby - symbols are objects
:active.class  # => Symbol
:active.to_s   # => "active"
```

```crystal
# Crystal - symbols are compile-time literals
:active.class  # Compile error!

# Use enums for type-safe constants
enum Status
  Active
  Inactive
end

Status::Active.class  # => Status
```

### No Symbol-to-Proc

```ruby
# Ruby
[1, 2, 3].map(&:to_s)  # => ["1", "2", "3"]
```

```crystal
# Crystal
[1, 2, 3].map(&.to_s)   # => ["1", "2", "3"]
# Note the dot after & - this is Crystal's syntax
```

### String Literals

```ruby
# Ruby - single or double quotes
name = 'John'
greeting = "Hello, #{name}"
```

```crystal
# Crystal - only double quotes for strings
name = "John"
greeting = "Hello, #{name}"

# Single quotes are for Chars
letter = 'A'  # This is a Char, not a String
```

### Hash Syntax

```ruby
# Ruby hash
hash = { key1: "value1", key2: "value2" }
hash[:key1]  # => "value1"
```

```crystal
# Crystal Hash - requires hash rocket
hash = { :key1 => "value1", :key2 => "value2" }
hash[:key1]  # => "value1"

# This creates a NamedTuple (immutable)
tuple = { key1: "value1", key2: "value2" }
tuple[:key1]  # => "value1"
```

### Regular Expressions

```ruby
# Ruby
matches = "hello".match(/l+/)
$1  # First capture group
$`  # Pre-match
$'  # Post-match
```

```crystal
# Crystal
matches = "hello".match(/l+/)
$1  # First capture group (same)
# No $` or $' - use:
matches.try(&.pre_match)   # Pre-match
matches.try(&.post_match)  # Post-match
```

### No Autosplat for Arrays

```ruby
# Ruby - automatic splatting
[[1, 2], [3, 4]].each do |a, b|
  puts "#{a}, #{b}"
end
```

```crystal
# Crystal - explicit unpacking needed
[[1, 2], [3, 4]].each do |(a, b)|
  puts "#{a}, #{b}"
end

# Or use tuples (which do autosplat)
[{1, 2}, {3, 4}].each do |a, b|
  puts "#{a}, #{b}"
end
```

### For Loops Don't Exist

```ruby
# Ruby
for i in 1..10
  puts i
end
```

```crystal
# Crystal - use each
(1..10).each do |i|
  puts i
end
```

### No `and`/`or` Keywords

```ruby
# Ruby
do_something and return true
do_something or raise "Error"
```

```crystal
# Crystal - use && and ||
do_something && return true
do_something || raise "Error"
```

## Type System Differences

### Nil Handling

```ruby
# Ruby - nil everywhere
name = nil
name.upcase  # NoMethodError at runtime
```

```crystal
# Crystal - nil is tracked
name = nil
name.upcase  # Compile error!

# Must handle nil
name : String? = get_name()
if name
  name.upcase  # OK - compiler knows it's not nil
end

# Or use try
name.try(&.upcase)  # Returns String? (can be nil)
```

### Array and Hash Access

```ruby
# Ruby - returns nil if not found
arr = [1, 2, 3]
arr[10]  # => nil

hash = {a: 1}
hash[:b]  # => nil
```

```crystal
# Crystal - raises exception
arr = [1, 2, 3]
arr[10]  # IndexError!

hash = {"a" => 1}
hash["b"]  # KeyError!

# Use ? methods for nil
arr[10]?   # => nil
hash["b"]?  # => nil
```

### Type Restrictions

```ruby
# Ruby - no type restrictions
def add(a, b)
  a + b
end
```

```crystal
# Crystal - optional type restrictions
def add(a : Number, b : Number)
  a + b
end

# Type inference often works
def add(a, b)
  a + b  # Works if + is defined for the types
end
```

## Method Differences

### No Method Missing

```ruby
# Ruby
class Dynamic
  def method_missing(name, *args)
    "Called #{name}"
  end
end
```

```crystal
# Crystal - use macros instead
class Dynamic
  macro method_missing(call)
    "Called {{call.name}}"
  end
end
```

### Private Methods

```ruby
# Ruby
class MyClass
  private

  def secret_method
    "secret"
  end
end
```

```crystal
# Crystal - per-method private
class MyClass
  private def secret_method
    "secret"
  end
end
```

### Properties Instead of attr\_\*

```ruby
# Ruby
class Person
  attr_reader :name
  attr_writer :age
  attr_accessor :email
end
```

```crystal
# Crystal
class Person
  getter name : String
  setter age : Int32
  property email : String

  # For boolean/nilable
  getter? admin : Bool = false
  property? nickname : String?
end
```

### Named Arguments Handling

```ruby
# Ruby - last hash becomes kwargs
def create(name, options = {})
  # options is a hash
end

create("John", age: 30, admin: true)
```

```crystal
# Crystal - real named arguments
def create(name : String, *, age : Int32, admin : Bool = false)
  # age and admin are actual parameters
end

create("John", age: 30, admin: true)
```

## Class and Module Differences

### Constants

```ruby
# Ruby - can be modified (with warning)
CONSTANT = 1
CONSTANT = 2  # Warning but works
```

```crystal
# Crystal - truly constant
CONSTANT = 1
CONSTANT = 2  # Compile error!
```

### Class Variables

```ruby
# Ruby - shared in hierarchy
class Parent
  @@var = 1
end

class Child < Parent
  @@var = 2  # Modifies Parent's @@var
end
```

```crystal
# Crystal - not shared in hierarchy
class Parent
  @@var = 1
end

class Child < Parent
  @@var = 2  # Child has its own @@var
end
```

### Include vs Extend

```ruby
# Ruby
module MyModule
  def instance_method; end

  def self.class_method; end
end

class MyClass
  include MyModule  # Adds instance methods
  extend MyModule   # Adds class methods
end
```

```crystal
# Crystal
module MyModule
  def instance_method; end

  def self.class_method; end
end

class MyClass
  include MyModule  # Adds instance methods
  extend MyModule   # Adds instance methods as class methods
end
```

## Iteration Differences

### Each Returns Nil

```ruby
# Ruby - each returns the collection
result = [1, 2, 3].each { |n| puts n }
result  # => [1, 2, 3]
```

```crystal
# Crystal - each returns nil
result = [1, 2, 3].each { |n| puts n }
result  # => nil

# Use tap to chain
[1, 2, 3].tap(&.each { |n| puts n })
```

### Select with Channels

Crystal has `select` for concurrent operations:

```crystal
channel1 = Channel(Int32).new
channel2 = Channel(String).new

spawn { channel1.send(1) }
spawn { channel2.send("hello") }

select
when value = channel1.receive
  puts "Got int: #{value}"
when value = channel2.receive
  puts "Got string: #{value}"
end
```

## Common Pitfalls

### 1. Forgetting Type Restrictions on Instance Variables

```crystal
class Person
  # Must specify types for instance/class variables
  @name : String
  @age : Int32

  def initialize(@name, @age)
  end
end
```

### 2. Using Single Quotes for Strings

```crystal
# Wrong
name = 'John'  # This is a Char error!

# Right
name = "John"
```

### 3. Expecting Symbols to Behave Like Objects

```crystal
# Wrong
status = :active
status.to_s  # Error!

# Right
status = :active
status.to_s  # Use string interpolation: "#{status}"
```

### 4. Forgetting Nil Checks

```crystal
# Wrong
def find_user(id)
  users[id]  # Might be nil
end

user = find_user(1)
user.name  # Error if user is nil!

# Right
if user = find_user(1)
  user.name  # Safe
end
```

### 5. Using Ruby's Hash Syntax

```crystal
# Wrong (creates NamedTuple)
config = { host: "localhost", port: 8080 }
config[:host] = "example.com"  # Error! NamedTuple is immutable

# Right (creates Hash)
config = { :host => "localhost", :port => 8080 }
config[:host] = "example.com"  # OK
```

## Best Practices for Migration

1. **Start with Type Annotations**: Be explicit about types initially
2. **Handle Nil Explicitly**: Use `Type?` for nilable types
3. **Use Enums Instead of Symbols**: For type-safe constants
4. **Leverage Compile Errors**: They're your friend
5. **Read the Compiler Output**: Crystal's error messages are very helpful
6. **Use Crystal Tools**:
   - `crystal tool format` - Auto-formatter
   - `crystal spec` - Run tests
   - `crystal docs` - Generate documentation

## Equivalent Gems/Shards

| Ruby Gem | Crystal Shard   | Notes             |
| -------- | --------------- | ----------------- |
| sinatra  | kemal           | Web framework     |
| rspec    | spec (built-in) | Testing framework |
| json     | json (built-in) | JSON parsing      |
| http     | http (built-in) | HTTP client       |
| redis    | redis           | Redis client      |
| pg       | crystal-pg      | PostgreSQL        |
| sidekiq  | mosquito        | Job processing    |

## Performance Considerations

Crystal is generally much faster than Ruby:

- No GIL (Global Interpreter Lock)
- Native machine code
- Stack-allocated structs
- Zero-cost abstractions

But remember:

- Compilation takes time
- Macros can increase compile time
- Generic instantiation creates code for each type

## Next Steps

Now that you understand the key differences, explore:

- [Type System](03-type-system.md) - Deep dive into Crystal's type system
- [Concurrency](04-concurrency.md) - Fibers and channels
- [Macros](07-macros.md) - Compile-time metaprogramming
