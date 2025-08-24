# Performance and Memory Management in Crystal

Crystal is designed for performance, compiling to efficient native code. Understanding how to write performant Crystal code is essential for building high-performance applications.

## Memory Management

Crystal uses the Boehm GC for automatic memory management, but understanding memory allocation patterns helps write efficient code.

### Stack vs Heap Allocation

```crystal
# Stack allocated (value types)
struct Point
  property x : Float64
  property y : Float64
  
  def initialize(@x, @y)
  end
end

# Heap allocated (reference types)
class Node
  property value : Int32
  property next : Node?
  
  def initialize(@value)
  end
end

# Structs are copied by value
p1 = Point.new(1.0, 2.0)  # Stack allocated
p2 = p1                    # Copied, not referenced
p2.x = 3.0
puts p1.x  # => 1.0 (unchanged)

# Classes are passed by reference
n1 = Node.new(1)           # Heap allocated
n2 = n1                    # Reference copied
n2.value = 2
puts n1.value  # => 2 (changed)
```

### Memory Efficient Data Structures

```crystal
# Use StaticArray for fixed-size arrays (stack allocated)
buffer = StaticArray(UInt8, 1024).new(0)

# Use Slice for efficient byte arrays
bytes = Bytes.new(1024)  # Slice(UInt8)

# String building
# Bad - creates many intermediate strings
result = ""
1000.times { |i| result += i.to_s }

# Good - uses a single buffer
result = String.build do |io|
  1000.times { |i| io << i }
end

# Array pre-allocation
# Bad - grows dynamically
arr = [] of Int32
10000.times { |i| arr << i }

# Good - pre-allocates capacity
arr = Array(Int32).new(10000)
10000.times { |i| arr << i }
```

### Object Pooling

```crystal
class ConnectionPool(T)
  @available = Channel(T).new
  @size : Int32
  
  def initialize(@size : Int32, &block : -> T)
    @size.times do
      @available.send(block.call)
    end
  end
  
  def acquire : T
    @available.receive
  end
  
  def release(connection : T)
    @available.send(connection)
  end
  
  def with_connection(&block : T ->)
    conn = acquire
    begin
      yield conn
    ensure
      release(conn)
    end
  end
end

# Usage
pool = ConnectionPool.new(10) { HTTP::Client.new("api.example.com") }

pool.with_connection do |client|
  response = client.get("/data")
  # Use response
end
```

## Optimization Techniques

### Compile-Time Optimization

```crystal
# Use constants for compile-time values
BUFFER_SIZE = 1024  # Compile-time constant
buffer = StaticArray(UInt8, BUFFER_SIZE).new(0)

# Compile-time computation with macros
macro compute_fibonacci(n)
  {% if n <= 1 %}
    {{n}}
  {% else %}
    {{compute_fibonacci(n - 1) + compute_fibonacci(n - 2)}}
  {% end %}
end

FIB_10 = compute_fibonacci(10)  # Computed at compile time

# Type restrictions enable optimizations
def process(items : Array(Int32))
  # Compiler knows exact type, can optimize
  items.sum
end
```

### Method Inlining

```crystal
# Small methods are often inlined
struct Vector2
  getter x : Float64
  getter y : Float64
  
  def initialize(@x : Float64, @y : Float64)
  end
  
  # Likely to be inlined
  def magnitude_squared
    x * x + y * y
  end
  
  # Force inline with @[AlwaysInline]
  @[AlwaysInline]
  def dot(other : Vector2)
    x * other.x + y * other.y
  end
end
```

### Avoiding Allocations

```crystal
# Reuse objects
class Parser
  @buffer = IO::Memory.new
  
  def parse(input : String)
    @buffer.clear
    # Use @buffer instead of creating new IO::Memory
  end
end

# Use mutation instead of creation
# Bad - creates new array
def process_data(data : Array(Int32))
  data.map { |x| x * 2 }
end

# Good - mutates in place
def process_data!(data : Array(Int32))
  data.map! { |x| x * 2 }
end

# Avoid intermediate arrays
# Bad
result = array.select(&.even?).map(&.*(2)).sum

# Good - single pass
result = array.sum do |x|
  x.even? ? x * 2 : 0
end
```

## Benchmarking

Crystal includes a built-in benchmarking module:

```crystal
require "benchmark"

# Simple benchmark
time = Benchmark.measure do
  # Code to benchmark
  sleep 1
end
puts "Execution time: #{time.total_seconds} seconds"

# Comparing implementations
n = 1_000_000
array = (1..n).to_a

Benchmark.ips do |x|
  x.report("each") do
    sum = 0
    array.each { |i| sum += i }
  end
  
  x.report("sum") do
    array.sum
  end
  
  x.report("reduce") do
    array.reduce(0) { |acc, i| acc + i }
  end
end

# Memory benchmark
initial_memory = GC.stats.heap_size

# Your code here
1000.times { Array(Int32).new(1000) }

final_memory = GC.stats.heap_size
puts "Memory used: #{final_memory - initial_memory} bytes"
```

## Profiling

### Built-in Profiling

```crystal
# Compile with debug symbols
# crystal build --release -d app.cr

# Use system profilers
# Linux: perf, valgrind
# macOS: Instruments
# Windows: Visual Studio Profiler

# Manual profiling
class Profiler
  @@timings = {} of String => Time::Span
  
  def self.measure(name : String, &block)
    start = Time.monotonic
    result = yield
    elapsed = Time.monotonic - start
    
    @@timings[name] ||= Time::Span.zero
    @@timings[name] += elapsed
    
    result
  end
  
  def self.report
    @@timings.each do |name, time|
      puts "#{name}: #{time.total_milliseconds}ms"
    end
  end
end

# Usage
Profiler.measure("database") do
  # Database query
end

Profiler.measure("processing") do
  # Data processing
end

Profiler.report
```

### GC Stats

```crystal
# Monitor GC performance
puts "Initial GC stats:"
pp GC.stats

# Your application code
10000.times { "string" * 100 }

GC.collect  # Force collection

puts "\nFinal GC stats:"
pp GC.stats

# Disable GC for performance-critical sections
GC.disable
begin
  # Performance-critical code
ensure
  GC.enable
end
```

## Optimization Strategies

### Algorithm Optimization

```crystal
# Choose efficient algorithms
# Bad - O(n²)
def has_duplicates?(array : Array(Int32))
  array.each_with_index do |x, i|
    array.each_with_index do |y, j|
      return true if i != j && x == y
    end
  end
  false
end

# Good - O(n)
def has_duplicates?(array : Array(Int32))
  seen = Set(Int32).new
  array.each do |x|
    return true if seen.includes?(x)
    seen << x
  end
  false
end
```

### Data Structure Selection

```crystal
# Choose appropriate data structures
# Array - indexed access, dynamic size
# StaticArray - fixed size, stack allocated
# Deque - fast push/pop at both ends
# Set - fast membership testing
# Hash - fast key-value lookup

# Example: Counting occurrences
def count_occurrences(items : Array(String))
  # Good - O(n) with hash
  counts = Hash(String, Int32).new(0)
  items.each { |item| counts[item] += 1 }
  counts
end
```

### I/O Optimization

```crystal
# Buffer I/O operations
# Bad - many small writes
file = File.open("output.txt", "w")
data.each do |line|
  file.puts line
end
file.close

# Good - buffered writes
File.open("output.txt", "w") do |file|
  io = IO::Buffered.new(file)
  data.each do |line|
    io.puts line
  end
  io.flush
end

# Use streaming for large files
# Bad - loads entire file
content = File.read("large.txt")
process(content)

# Good - streaming
File.open("large.txt") do |file|
  file.each_line do |line|
    process(line)
  end
end
```

### Concurrency for Performance

```crystal
# Parallel processing with fibers
def parallel_map(items : Array(T), workers = 8, &block : T -> U) forall T, U
  channel = Channel(Tuple(Int32, U)).new
  
  items.each_with_index do |item, index|
    spawn do
      result = block.call(item)
      channel.send({index, result})
    end
  end
  
  results = Array(U?).new(items.size, nil)
  items.size.times do
    index, result = channel.receive
    results[index] = result
  end
  
  results.map(&.not_nil!)
end

# Usage
data = (1..1000).to_a
results = parallel_map(data) { |x| expensive_computation(x) }
```

## Binary Protocol Optimization

For MTProto implementation, binary protocol handling is crucial:

```crystal
# Efficient binary reading/writing
class BinaryReader
  def initialize(@io : IO)
    @buffer = Bytes.new(8)  # Reuse buffer
  end
  
  def read_int32 : Int32
    @io.read_fully(@buffer[0, 4])
    IO::ByteFormat::LittleEndian.decode(Int32, @buffer)
  end
  
  def read_int64 : Int64
    @io.read_fully(@buffer)
    IO::ByteFormat::LittleEndian.decode(Int64, @buffer)
  end
  
  def read_bytes(size : Int32) : Bytes
    bytes = Bytes.new(size)
    @io.read_fully(bytes)
    bytes
  end
end

# Zero-copy string handling
def read_string(io : IO, size : Int32) : String
  bytes = Bytes.new(size)
  io.read_fully(bytes)
  String.new(bytes)  # Creates string without copying bytes
end

# Efficient binary building
class BinaryBuilder
  def initialize(@io : IO = IO::Memory.new)
  end
  
  def write_int32(value : Int32)
    @io.write_bytes(value, IO::ByteFormat::LittleEndian)
  end
  
  def write_bytes(bytes : Bytes)
    @io.write(bytes)
  end
  
  def to_slice
    if io = @io.as?(IO::Memory)
      io.to_slice
    else
      raise "Not an IO::Memory"
    end
  end
end
```

## Common Performance Pitfalls

### 1. String Concatenation in Loops

```crystal
# Bad
result = ""
1000.times { |i| result += i.to_s }

# Good
result = String.build do |str|
  1000.times { |i| str << i }
end
```

### 2. Unnecessary Allocations

```crystal
# Bad - creates intermediate array
def sum_even(numbers)
  numbers.select(&.even?).sum
end

# Good - single pass, no allocation
def sum_even(numbers)
  numbers.sum { |n| n.even? ? n : 0 }
end
```

### 3. Repeated Regex Compilation

```crystal
# Bad - compiles regex each time
def valid_email?(email)
  email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
end

# Good - compile once
EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

def valid_email?(email)
  email =~ EMAIL_REGEX
end
```

### 4. Not Using Built-in Methods

```crystal
# Bad - manual implementation
def array_max(arr)
  max = arr[0]
  arr.each { |x| max = x if x > max }
  max
end

# Good - built-in optimized
def array_max(arr)
  arr.max
end
```

## Release Mode Optimizations

Always benchmark and profile in release mode:

```bash
# Development build (slow, with debug info)
crystal build app.cr

# Release build (optimized)
crystal build --release app.cr

# Release with debug symbols (for profiling)
crystal build --release -d app.cr

# Static linking (single binary)
crystal build --release --static app.cr

# Link-time optimization
crystal build --release --lto=thin app.cr
```

## Performance Best Practices

1. **Measure, don't guess**: Always benchmark before optimizing
2. **Use release mode**: Development builds are much slower
3. **Prefer structs**: For small, immutable data
4. **Pre-allocate collections**: When size is known
5. **Avoid premature optimization**: Write clear code first
6. **Use appropriate data structures**: Set for membership, Hash for lookup
7. **Minimize allocations**: Reuse objects when possible
8. **Buffer I/O**: Don't write byte by byte
9. **Profile regularly**: Find actual bottlenecks
10. **Consider parallelism**: For CPU-bound tasks with -Dpreview_mt

Crystal's performance is one of its strongest features. With proper optimization techniques, Crystal programs can match or exceed C performance while maintaining Ruby-like expressiveness.

Next: [Macros and Metaprogramming](07-macros.md)