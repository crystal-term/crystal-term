# Crystal Concurrency Model

Crystal provides lightweight concurrency through fibers and channels, inspired by CSP (Communicating Sequential Processes). Currently, Crystal supports concurrency but not parallelism by default.

## Core Concepts

### Concurrency vs Parallelism

- **Concurrency**: Multiple tasks making progress (not necessarily simultaneously)
- **Parallelism**: Multiple tasks executing simultaneously on different CPU cores

Crystal currently runs in a single OS thread (except GC), but experimental multi-threading support is available with `-Dpreview_mt`.

### Key Components

1. **Fibers**: Lightweight execution units (like green threads)
2. **Event Loop**: Handles async I/O operations
3. **Channels**: Communication between fibers
4. **Runtime Scheduler**: Manages fiber execution

## Fibers

Fibers are cooperative, lightweight threads managed by Crystal's runtime.

### Creating Fibers

```crystal
# Basic fiber spawn
spawn do
  puts "Hello from fiber!"
  sleep 1
  puts "Fiber done!"
end

# Spawn with a name (for debugging)
spawn(name: "worker") do
  puts "Working..."
end

# Spawn with method call
def process(id : Int32)
  puts "Processing #{id}"
end

spawn process(1)
spawn process(2)
```

### Fiber Execution

```crystal
# Fibers don't run immediately
spawn do
  puts "This might not print!"
end
# Program exits before fiber runs

# Use sleep to keep program alive
spawn do
  puts "This will print"
end
sleep 0.1

# Or use Fiber.yield
spawn do
  puts "This will also print"
end
Fiber.yield

# Wait forever
spawn do
  loop do
    puts "Running..."
    sleep 1
  end
end
sleep  # No argument = sleep forever
```

### Fiber Control

```crystal
# Get current fiber
current = Fiber.current
puts "Running in fiber: #{current.name || "main"}"

# Yield to scheduler
10.times do |i|
  spawn do
    loop do
      puts "Fiber #{i} working"
      Fiber.yield  # Give other fibers a chance
    end
  end
end
sleep 1

# Check if fiber is running
fiber = spawn do
  sleep 1
end

puts fiber.dead?  # false initially
sleep 2
puts fiber.dead?  # true after completion
```

## Channels

Channels provide safe communication between fibers.

### Basic Channel Usage

```crystal
# Create unbuffered channel
channel = Channel(Int32).new

# Send and receive
spawn do
  channel.send(42)
end

value = channel.receive
puts value  # => 42

# Channel with specific type
msg_channel = Channel(String).new

spawn do
  msg_channel.send("Hello")
  msg_channel.send("World")
end

puts msg_channel.receive  # => "Hello"
puts msg_channel.receive  # => "World"
```

### Buffered Channels

```crystal
# Buffered channel (doesn't block until full)
channel = Channel(Int32).new(capacity: 3)

# Can send without blocking
channel.send(1)  # Doesn't block
channel.send(2)  # Doesn't block
channel.send(3)  # Doesn't block
# channel.send(4)  # Would block until someone receives

# Receive all values
3.times do
  puts channel.receive
end
```

### Channel Patterns

```crystal
# Multiple producers
channel = Channel(Int32).new

3.times do |i|
  spawn do
    10.times do |j|
      channel.send(i * 10 + j)
      sleep 0.1
    end
  end
end

# Single consumer
spawn do
  30.times do
    puts channel.receive
  end
end

sleep 4

# Fan-out pattern
source = Channel(Int32).new
workers = 3

workers.times do |i|
  spawn(name: "worker-#{i}") do
    loop do
      value = source.receive
      puts "Worker #{i} processing #{value}"
      sleep 0.1
    end
  end
end

# Send work
10.times { |i| source.send(i) }
sleep 2
```

### Closing Channels

```crystal
channel = Channel(Int32).new

spawn do
  5.times do |i|
    channel.send(i)
  end
  channel.close
end

# Safe iteration
while value = channel.receive?
  puts value
end

# Or use each (blocks until closed)
channel = Channel(String).new
spawn do
  ["one", "two", "three"].each do |word|
    channel.send(word)
  end
  channel.close
end

channel.each do |word|
  puts word
end
```

## Select Statement

Select allows waiting on multiple channels:

```crystal
ch1 = Channel(Int32).new
ch2 = Channel(String).new
timeout = Channel(Nil).new

# Timeout fiber
spawn do
  sleep 2
  timeout.send(nil)
end

# Producer fibers
spawn do
  sleep 0.5
  ch1.send(42)
end

spawn do
  sleep 1
  ch2.send("hello")
end

# Select from multiple channels
loop do
  select
  when value = ch1.receive
    puts "Got int: #{value}"
  when value = ch2.receive
    puts "Got string: #{value}"
  when timeout.receive
    puts "Timeout!"
    break
  end
end
```

### Non-blocking Select

```crystal
ch = Channel(Int32).new

select
when ch.send(42)
  puts "Sent value"
else
  puts "Channel not ready"
end

select
when value = ch.receive
  puts "Got: #{value}"
else
  puts "No value available"
end
```

## Common Concurrency Patterns

### Worker Pool

```crystal
class WorkerPool
  def initialize(@size : Int32)
    @jobs = Channel(Proc(Nil)).new
    @size.times { spawn_worker }
  end

  private def spawn_worker
    spawn do
      loop do
        job = @jobs.receive
        job.call
      rescue Channel::ClosedError
        break
      end
    end
  end

  def perform(&block : ->)
    @jobs.send(block)
  end

  def shutdown
    @jobs.close
  end
end

# Usage
pool = WorkerPool.new(4)

10.times do |i|
  pool.perform do
    puts "Task #{i} on fiber #{Fiber.current.name}"
    sleep 0.1
  end
end

sleep 2
pool.shutdown
```

### Future/Promise Pattern

```crystal
class Future(T)
  @channel = Channel(T | Exception).new

  def initialize(&block : -> T)
    spawn do
      begin
        value = block.call
        @channel.send(value)
      rescue ex
        @channel.send(ex)
      end
    end
  end

  def get : T
    result = @channel.receive
    case result
    when Exception
      raise result
    else
      result.as(T)
    end
  end
end

# Usage
future = Future.new do
  sleep 1
  42
end

puts "Doing other work..."
result = future.get  # Blocks until ready
puts "Result: #{result}"
```

### Rate Limiting

```crystal
class RateLimiter
  def initialize(@rate : Int32, @per : Time::Span)
    @channel = Channel(Nil).new(@rate)
    @rate.times { @channel.send(nil) }

    spawn do
      loop do
        sleep @per / @rate
        @channel.send(nil) rescue Channel::ClosedError
      end
    end
  end

  def perform(&block)
    @channel.receive
    block.call
  end
end

# 5 requests per second
limiter = RateLimiter.new(5, 1.second)

10.times do |i|
  spawn do
    limiter.perform do
      puts "Request #{i} at #{Time.local}"
    end
  end
end

sleep 3
```

### Pub/Sub Pattern

```crystal
class PubSub(T)
  @subscribers = [] of Channel(T)
  @mutex = Mutex.new

  def subscribe : Channel(T)
    channel = Channel(T).new
    @mutex.synchronize do
      @subscribers << channel
    end
    channel
  end

  def publish(message : T)
    @mutex.synchronize do
      @subscribers.each do |channel|
        spawn { channel.send(message) }
      end
    end
  end
end

# Usage
pubsub = PubSub(String).new

# Subscribers
3.times do |i|
  channel = pubsub.subscribe
  spawn do
    channel.each do |msg|
      puts "Subscriber #{i}: #{msg}"
    end
  end
end

# Publisher
spawn do
  ["Hello", "World", "From", "PubSub"].each do |word|
    pubsub.publish(word)
    sleep 0.5
  end
end

sleep 3
```

## Synchronization Primitives

### Mutex

```crystal
class Counter
  @value = 0
  @mutex = Mutex.new

  def increment
    @mutex.synchronize do
      @value += 1
    end
  end

  def value
    @mutex.synchronize { @value }
  end
end

counter = Counter.new

10.times do
  spawn do
    1000.times { counter.increment }
  end
end

sleep 1
puts counter.value  # => 10000
```

### WaitGroup

```crystal
class WaitGroup
  @counter = 0
  @channel = Channel(Nil).new

  def add(n = 1)
    @counter += n
  end

  def done
    @counter -= 1
    @channel.send(nil) if @counter == 0
  end

  def wait
    @channel.receive if @counter > 0
  end
end

# Usage
wg = WaitGroup.new

5.times do |i|
  wg.add
  spawn do
    puts "Worker #{i} starting"
    sleep rand(0.1..0.5)
    puts "Worker #{i} done"
    wg.done
  end
end

wg.wait
puts "All workers completed"
```

## Best Practices

### 1. Avoid Shared State

```crystal
# Bad - shared mutable state
total = 0
10.times do
  spawn do
    total += 1  # Race condition!
  end
end

# Good - use channels
channel = Channel(Int32).new
10.times do
  spawn do
    channel.send(1)
  end
end

total = 0
10.times do
  total += channel.receive
end
```

### 2. Handle Channel Closing

```crystal
# Always handle closed channels
channel = Channel(Int32).new

spawn do
  5.times { |i| channel.send(i) }
  channel.close
end

# Safe receiving
while value = channel.receive?
  puts value
end

# Or handle exception
begin
  loop do
    puts channel.receive
  end
rescue Channel::ClosedError
  puts "Channel closed"
end
```

### 3. Timeout Handling

```crystal
def with_timeout(seconds : Number, &block : -> T) : T? forall T
  result_channel = Channel(T).new
  timeout_channel = Channel(Nil).new

  spawn do
    result_channel.send(block.call)
  end

  spawn do
    sleep seconds
    timeout_channel.send(nil)
  end

  select
  when result = result_channel.receive
    result
  when timeout_channel.receive
    nil
  end
end

# Usage
result = with_timeout(2) do
  sleep 1
  "Success!"
end
puts result  # => "Success!"

result = with_timeout(1) do
  sleep 2
  "Too slow"
end
puts result  # => nil
```

### 4. Graceful Shutdown

```crystal
class Worker
  @shutdown = Channel(Nil).new
  @done = Channel(Nil).new

  def start
    spawn do
      loop do
        select
        when @shutdown.receive
          cleanup
          @done.send(nil)
          break
        else
          # Do work
          do_work
          Fiber.yield
        end
      end
    end
  end

  def stop
    @shutdown.send(nil)
    @done.receive
  end

  private def do_work
    puts "Working..."
    sleep 0.1
  end

  private def cleanup
    puts "Cleaning up..."
  end
end
```

## Performance Considerations

1. **Fiber Stack Size**: Each fiber has 8MB virtual memory (4KB initial)
2. **Context Switching**: Cheaper than OS threads but not free
3. **Channel Operations**: Buffered channels can reduce blocking
4. **I/O Bound**: Crystal excels at I/O-bound concurrent tasks
5. **CPU Bound**: Use worker pools to avoid blocking the event loop

## Debugging Concurrent Code

```crystal
# Name your fibers
spawn(name: "processor") do
  puts Fiber.current.name  # => "processor"
end

# Add logging
spawn do
  puts "[#{Time.local}] Starting task"
  # work...
  puts "[#{Time.local}] Task complete"
end

# Use select with else for debugging
channel = Channel(Int32).new

select
when value = channel.receive
  puts "Got: #{value}"
else
  puts "Channel empty at #{Time.local}"
end
```

## Multi-threading (Experimental)

Enable with `-Dpreview_mt`:

```bash
crystal build app.cr -Dpreview_mt
```

This allows true parallelism but requires careful synchronization:

```crystal
# With preview_mt, this runs in parallel
mutex = Mutex.new
sum = 0

workers = 4
done = Channel(Nil).new

workers.times do
  spawn do
    partial = 0
    (1..1000000).each { |i| partial += i }

    mutex.synchronize do
      sum += partial
    end

    done.send(nil)
  end
end

workers.times { done.receive }
puts sum
```

## Common Pitfalls

1. **Forgetting to yield/sleep**: Main fiber exits before spawned fibers run
2. **Deadlocks**: Circular channel dependencies
3. **Resource leaks**: Not closing channels
4. **Race conditions**: Sharing mutable state without synchronization
5. **Blocking operations**: Blocking the event loop with CPU-intensive work

Crystal's concurrency model is powerful for I/O-bound tasks, web servers, and coordinating parallel work. Understanding fibers and channels is essential for building efficient Crystal applications.

Next: [Standard Library Overview](05-standard-library.md)
