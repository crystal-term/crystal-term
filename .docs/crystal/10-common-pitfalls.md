# Common Pitfalls for Ruby Developers

This guide covers common mistakes and misconceptions when transitioning from Ruby to Crystal, with specific focus on pitfalls that affect MTProto implementation.

## Compilation and Development Workflow

### Pitfall: Expecting Immediate Execution

```ruby
# Ruby - immediate execution
puts "Hello"  # Runs immediately
```

```crystal
# Crystal - requires compilation
puts "Hello"  # Must compile first

# Wrong workflow
# crystal hello.cr    # Compiles and runs (development mode)
# ./hello             # Fails - no executable created

# Right workflow
crystal build hello.cr  # Creates executable
./hello                 # Runs the executable

# Or for development
crystal run hello.cr    # Compile and run in one step
```

### Pitfall: Forgetting Release Mode

```bash
# Development build (very slow)
crystal build app.cr

# Release build (optimized - always use for benchmarks)
crystal build --release app.cr

# The performance difference can be 10x or more!
```

## Type System Misunderstandings

### Pitfall: Assuming Duck Typing

```ruby
# Ruby - duck typing works
def process(obj)
  obj.to_s  # Works with any object that responds to to_s
end

process(42)      # Works
process("hello") # Works
process([1,2,3]) # Works
```

```crystal
# Crystal - static typing
def process(obj)
  obj.to_s  # Compiler needs to know obj's type
end

# Wrong - this won't compile
process(42)      # Error: can't infer type
process("hello") # Error: can't infer type

# Right - use generics or union types
def process(obj : T) forall T
  obj.to_s
end

# Or specific types
def process(obj : String | Int32 | Array(Int32))
  obj.to_s
end
```

### Pitfall: Nil Surprises

```ruby
# Ruby - nil everywhere
user = users[id]  # Might be nil
name = user.name  # RuntimeError if user is nil
```

```crystal
# Crystal - nil is tracked at compile time
user = users[id]?  # Returns User?
name = user.name   # Compile error! user might be nil

# Right way
if user = users[id]?
  name = user.name  # Safe - compiler knows user isn't nil
end

# Or use try
name = users[id]?.try(&.name)

# Common mistake with instance variables
class Person
  def initialize(@name : String?)  # name can be nil
  end
  
  def greet
    puts "Hello, #{@name.upcase}"  # Error! @name might be nil
  end
  
  def greet_safely
    if name = @name
      puts "Hello, #{name.upcase}"  # Safe
    else
      puts "Hello, stranger!"
    end
  end
end
```

### Pitfall: Symbol Misuse

```ruby
# Ruby - symbols are objects
status = :active
status.to_s        # "active"
status.class       # Symbol
statuses = [:active, :inactive]
```

```crystal
# Crystal - symbols are compile-time literals
status = :active
status.to_s        # Compile error!
status.class       # Compile error!

# Right way - use enums
enum Status
  Active
  Inactive
end

status = Status::Active
status.to_s        # "Active"

# Or use strings if you need runtime flexibility
status = "active"
status.upcase      # "ACTIVE"
```

### Pitfall: Array/Hash Access Expectations

```ruby
# Ruby - returns nil for missing elements
arr = [1, 2, 3]
arr[10]           # nil

hash = {a: 1}
hash[:missing]    # nil
```

```crystal
# Crystal - raises exceptions
arr = [1, 2, 3]
arr[10]           # IndexError!

hash = {:a => 1}
hash[:missing]    # KeyError!

# Right way - use ? methods
arr[10]?          # nil
hash[:missing]?   # nil

# Or check bounds
if arr.size > 10
  value = arr[10]  # Safe
end
```

## String and Character Handling

### Pitfall: Single Quote Confusion

```ruby
# Ruby - both create strings
name = 'John'
name = "John"
```

```crystal
# Crystal - different types
name = 'J'        # Char (single character)
name = "John"     # String

# Wrong
names = ['John', 'Jane']  # Error! Array of Chars, not Strings

# Right
names = ["John", "Jane"]  # Array of Strings
char = 'J'               # Single character
```

### Pitfall: String Mutability Assumptions

```ruby
# Ruby - strings are mutable
str = "hello"
str << " world"   # Modifies str
str.upcase!       # Modifies str
```

```crystal
# Crystal - strings are immutable
str = "hello"
str << " world"   # Error! No << method
str.upcase!       # Error! No upcase! method

# Right way
str = "hello"
str = str + " world"  # Creates new string
str = str.upcase      # Creates new string

# Use String.build for efficient building
result = String.build do |io|
  io << "hello"
  io << " "
  io << "world"
end
```

## Hash and NamedTuple Confusion

### Pitfall: Ruby Hash Syntax Creates NamedTuple

```ruby
# Ruby - both create hashes
user1 = {name: "John", age: 30}
user2 = {:name => "John", :age => 30}
user1[:name] = "Jane"  # Works
```

```crystal
# Crystal - different types!
user1 = {name: "John", age: 30}           # NamedTuple (immutable)
user2 = {:name => "John", :age => 30}     # Hash (mutable)

user1[:name] = "Jane"  # Error! NamedTuple is immutable
user2[:name] = "Jane"  # Works - Hash is mutable

# NamedTuple access
user1[:name]     # "John"
user1.name       # "John" - also works

# Hash access
user2[:name]     # "John"
user2.name       # Error! Hash doesn't have name method
```

### Pitfall: Hash Type Inference

```crystal
# This creates Hash(Symbol, String | Int32)
hash = {:name => "John", :age => 30}

# Later assignments must match
hash[:active] = true     # Error! Bool not in String | Int32
hash[:name] = 42         # OK - Int32 is valid

# Be explicit about types
hash = {} of Symbol => String | Int32 | Bool
hash[:name] = "John"
hash[:age] = 30
hash[:active] = true    # Now this works
```

## Method and Block Differences

### Pitfall: Block Return Value Expectations

```ruby
# Ruby - each returns the receiver
result = [1, 2, 3].each { |n| puts n }
result  # [1, 2, 3]

# Can chain methods
[1, 2, 3].each { |n| puts n }.map { |n| n * 2 }
```

```crystal
# Crystal - each returns nil
result = [1, 2, 3].each { |n| puts n }
result  # nil

# Can't chain like Ruby
[1, 2, 3].each { |n| puts n }.map { |n| n * 2 }  # Error!

# Use tap for chaining
[1, 2, 3].tap(&.each { |n| puts n }).map { |n| n * 2 }
```

### Pitfall: Splat Behavior Differences

```ruby
# Ruby - automatic splatting
[[1, 2], [3, 4]].each do |a, b|
  puts "#{a}, #{b}"  # Works
end
```

```crystal
# Crystal - no automatic splatting
[[1, 2], [3, 4]].each do |a, b|
  puts "#{a}, #{b}"  # Error! Too many block arguments
end

# Right way - explicit unpacking
[[1, 2], [3, 4]].each do |(a, b)|
  puts "#{a}, #{b}"  # Works
end

# Or use tuples (which do autosplat)
[{1, 2}, {3, 4}].each do |a, b|
  puts "#{a}, #{b}"  # Works
end
```

### Pitfall: Method Visibility

```ruby
# Ruby - private affects following methods
class MyClass
  def public_method; end
  
  private
  
  def private_method; end
  def another_private; end
end
```

```crystal
# Crystal - private is per-method
class MyClass
  def public_method; end
  
  private def private_method; end
  
  def another_public; end      # This is public!
  private def another_private; end
end
```

## Metaprogramming Limitations

### Pitfall: Runtime Metaprogramming Expectations

```ruby
# Ruby - runtime metaprogramming
class User
  def method_missing(name, *args)
    if name.to_s.start_with?('find_by_')
      field = name.to_s.sub('find_by_', '')
      # Dynamic method implementation
    end
  end
end

user = User.new
user.find_by_name("John")  # Works at runtime
```

```crystal
# Crystal - no runtime metaprogramming
class User
  # method_missing doesn't exist!
  
  # Use macros for compile-time generation
  macro method_missing(call)
    {% if call.name.stringify.starts_with?("find_by_") %}
      # Generate method at compile time
    {% else %}
      {% raise "Unknown method #{call.name}" %}
    {% end %}
  end
end
```

### Pitfall: eval and define_method

```ruby
# Ruby - dynamic evaluation
code = "def greet; puts 'hello'; end"
eval(code)              # Creates method at runtime

User.define_method(:name) do
  @name
end
```

```crystal
# Crystal - no eval, no define_method
# Use macros instead
macro define_getter(name)
  def {{name}}
    @{{name}}
  end
end

class User
  @name : String
  
  def initialize(@name)
  end
  
  define_getter name  # Generates getter at compile time
end
```

## File and I/O Pitfalls

### Pitfall: Automatic String Encoding

```ruby
# Ruby - files read as strings with encoding
data = File.read("binary.dat")  # String with encoding
data.encoding                   # Shows encoding
```

```crystal
# Crystal - files read as bytes by default
data = File.read("binary.dat")  # String (UTF-8 assumed)

# For binary data, be explicit
bytes = File.read("binary.dat").to_slice  # Bytes
# Or
File.open("binary.dat", "rb") do |file|
  bytes = Bytes.new(file.size)
  file.read(bytes)
end
```

### Pitfall: IO Buffer Expectations

```crystal
# Wrong - assuming buffered I/O
File.open("large.txt") do |file|
  1_000_000.times do
    file.puts "line"  # Inefficient! Direct I/O calls
  end
end

# Right - use buffering
File.open("large.txt", "w") do |file|
  buffered = IO::Buffered.new(file)
  1_000_000.times do
    buffered.puts "line"
  end
  buffered.flush
end
```

## Binary Protocol Pitfalls

### Pitfall: Binary Data as Strings

```ruby
# Ruby - binary data often as strings
data = "\x01\x02\x03\x04"
data.bytes  # [1, 2, 3, 4]
```

```crystal
# Crystal - use Bytes for binary data
# Wrong
data = "\u{01}\u{02}\u{03}\u{04}"  # String (inefficient)

# Right
data = Bytes[1, 2, 3, 4]          # Bytes (efficient)
# Or
data = Slice(UInt8).new(4)
data[0] = 1_u8
data[1] = 2_u8
```

### Pitfall: Endianness Assumptions

```crystal
# Wrong - assuming system endianness
io = IO::Memory.new
io.write_bytes(0x12345678)  # System endianness

# Right - explicit endianness for protocols
io = IO::Memory.new
io.write_bytes(0x12345678, IO::ByteFormat::LittleEndian)
io.write_bytes(0x12345678, IO::ByteFormat::BigEndian)
```

## Concurrency Pitfalls

### Pitfall: Thread Expectations

```ruby
# Ruby - threads with shared memory
@counter = 0
threads = 10.times.map do
  Thread.new do
    1000.times { @counter += 1 }
  end
end
threads.each(&:join)
puts @counter  # Race condition!
```

```crystal
# Crystal - fibers, no parallelism by default
@counter = 0
10.times do
  spawn do
    1000.times { @counter += 1 }
  end
end
sleep 1
puts @counter  # No race condition (single thread)

# For parallelism (with -Dpreview_mt), use synchronization
mutex = Mutex.new
@counter = 0
10.times do
  spawn do
    1000.times do
      mutex.synchronize { @counter += 1 }
    end
  end
end
```

### Pitfall: Fiber Execution Assumptions

```crystal
# Wrong - expecting immediate execution
spawn do
  puts "This might not print!"
end
# Program exits before fiber runs

# Right - ensure fibers have time to run
spawn do
  puts "This will print"
end
sleep 0.1  # Give fibers time

# Or use channels to wait
done = Channel(Nil).new
spawn do
  puts "Working..."
  done.send(nil)
end
done.receive  # Wait for completion
```

## Error Handling Pitfalls

### Pitfall: Exception Class Hierarchy

```ruby
# Ruby - StandardError for catchable errors
begin
  risky_operation
rescue StandardError => e
  # Catches most user errors
end
```

```crystal
# Crystal - Exception for all errors
begin
  risky_operation
rescue Exception => e  # Catches everything (usually too broad)
  # Handle error
end

# Better - catch specific exceptions
begin
  risky_operation
rescue IO::Error => e
  # Handle I/O errors
rescue ArgumentError => e
  # Handle argument errors
end
```

### Pitfall: Expecting `retry` Keyword

```ruby
# Ruby - retry keyword
retries = 3
begin
  unreliable_operation
rescue NetworkError
  retries -= 1
  retry if retries > 0
  raise
end
```

```crystal
# Crystal - no retry keyword, use loop
retries = 3
loop do
  begin
    unreliable_operation
    break  # Success
  rescue NetworkError
    retries -= 1
    if retries > 0
      next  # Try again
    else
      raise  # Give up
    end
  end
end
```

## Performance Misunderstandings

### Pitfall: Premature Optimization

```crystal
# Wrong - optimizing before measuring
def process_data(data)
  # Complex optimization that might not be needed
  cached_results = @cache ||= {} of String => Result
  # ...
end

# Right - write clear code first, then optimize
def process_data(data)
  # Simple, clear implementation
  transform_data(data)
end

# Then benchmark and optimize bottlenecks
```

### Pitfall: Ignoring Release Mode

```crystal
# Wrong - benchmarking in development mode
time = Benchmark.realtime do
  slow_operation
end

# Right - always benchmark in release mode
# crystal build --release benchmark.cr
# ./benchmark
```

## Summary

The key to avoiding these pitfalls:

1. **Embrace static typing** - don't fight the type system
2. **Use nil-safe patterns** - handle nil explicitly
3. **Understand compilation** - Crystal is not Ruby
4. **Learn Crystal idioms** - don't just translate Ruby code
5. **Test thoroughly** - catch type errors early
6. **Read compiler errors** - they're usually helpful
7. **Use release mode** - for any performance testing
8. **Leverage the type system** - it catches bugs at compile time

Understanding these differences helps you write idiomatic Crystal code and avoid frustrating debugging sessions. The transition from Ruby to Crystal is rewarding once you embrace the static typing and compile-time safety.

This completes the Crystal documentation for the Tektite project. Each guide builds upon the previous ones to provide a comprehensive understanding of Crystal for MTProto implementation.