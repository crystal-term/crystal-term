# Testing with Spectator in Crystal

Crystal includes a built-in testing framework called Spec, but for the Tektite project, we'll use Spectator, which provides more advanced features and better RSpec compatibility.

## Spectator vs Spec

Spectator is a modern testing framework inspired by RSpec that offers:
- Better matchers and DSL
- Nested contexts and shared examples  
- Mock objects and stubbing
- Parameterized tests
- Advanced hooks

## Setting Up Spectator

Add to your `shard.yml`:

```yaml
development_dependencies:
  spectator:
    gitlab: arctic-fox/spectator
    version: ~> 0.11.0
```

Create `spec/spec_helper.cr`:

```crystal
require "spectator"

# Configure Spectator
Spectator.configure do |config|
  config.fail_fast = false
  config.randomize = true
  config.profile = 10  # Show 10 slowest tests
end

# Common test utilities
module TestHelpers
  def sample_data
    {"name" => "Test", "value" => 42}
  end
  
  def create_temp_file(content = "test")
    file = File.tempfile("test")
    file.print(content)
    file.flush
    file.close
    file.path
  end
end

# Include helpers in all specs
Spectator.configure do |config|
  config.include TestHelpers
end
```

## Basic Test Structure

```crystal
require "./spec_helper"

Spectator.describe Calculator do
  # Use subject for the thing being tested
  subject { Calculator.new }
  
  # Use let for test data (lazy evaluation)
  let(a) { 10 }
  let(b) { 5 }
  
  describe "#add" do
    it "adds two numbers" do
      expect(subject.add(a, b)).to eq(15)
    end
    
    it "handles negative numbers" do
      expect(subject.add(-5, 3)).to eq(-2)
    end
  end
  
  describe "#divide" do
    it "divides two numbers" do
      expect(subject.divide(a, b)).to eq(2.0)
    end
    
    context "when dividing by zero" do
      it "raises an error" do
        expect { subject.divide(a, 0) }.to raise_error(DivisionByZeroError)
      end
    end
  end
end
```

## Matchers

Spectator provides comprehensive matchers:

```crystal
Spectator.describe "Matchers" do
  describe "equality matchers" do
    it "checks equality" do
      expect(2 + 2).to eq(4)
      expect("hello").to eq("hello")
      expect([1, 2, 3]).to eq([1, 2, 3])
    end
    
    it "checks identity" do
      str = "test"
      expect(str).to be(str)
    end
    
    it "checks approximate equality" do
      expect(3.14159).to be_within(0.001).of(3.142)
    end
  end
  
  describe "comparison matchers" do
    it "compares values" do
      expect(10).to be > 5
      expect(5).to be < 10
      expect(5).to be <= 5
      expect(10).to be >= 10
    end
  end
  
  describe "type matchers" do
    it "checks types" do
      expect("string").to be_a(String)
      expect(42).to be_a(Int32)
      expect(nil).to be_nil
    end
  end
  
  describe "collection matchers" do
    let(array) { [1, 2, 3, 4, 5] }
    
    it "checks collection contents" do
      expect(array).to contain(3)
      expect(array).to contain_exactly(1, 2, 3, 4, 5)
      expect(array).to have(5).items
      expect(array).to start_with(1, 2)
      expect(array).to end_with(4, 5)
    end
    
    it "checks if empty" do
      expect([] of Int32).to be_empty
      expect(array).not_to be_empty
    end
  end
  
  describe "string matchers" do
    let(text) { "Hello, Crystal World!" }
    
    it "matches strings" do
      expect(text).to contain("Crystal")
      expect(text).to start_with("Hello")
      expect(text).to end_with("World!")
      expect(text).to match(/Crystal/)
    end
  end
  
  describe "error matchers" do
    it "expects errors" do
      expect { raise "boom" }.to raise_error
      expect { raise ArgumentError.new("bad") }.to raise_error(ArgumentError)
      expect { raise ArgumentError.new("bad") }.to raise_error(ArgumentError, "bad")
      expect { 42 }.not_to raise_error
    end
  end
end
```

## Test Organization

### Contexts and Nested Describes

```crystal
Spectator.describe User do
  subject { User.new(name, email) }
  
  let(name) { "John Doe" }
  let(email) { "john@example.com" }
  
  describe "#valid?" do
    context "with valid data" do
      it "returns true" do
        expect(subject.valid?).to be_true
      end
    end
    
    context "with invalid email" do
      let(email) { "invalid-email" }
      
      it "returns false" do
        expect(subject.valid?).to be_false
      end
      
      it "has email error" do
        subject.valid?
        expect(subject.errors).to contain("Email is invalid")
      end
    end
    
    context "with missing name" do
      let(name) { "" }
      
      it "returns false" do
        expect(subject.valid?).to be_false
      end
    end
  end
end
```

### Shared Examples

```crystal
# Define shared examples
Spectator.shared_examples "a collection" do
  it "responds to size" do
    expect(subject).to respond_to(:size)
  end
  
  it "responds to empty?" do
    expect(subject).to respond_to(:empty?)
  end
  
  it "is enumerable" do
    expect(subject).to be_a(Enumerable)
  end
end

# Use shared examples
Spectator.describe Array do
  subject { [1, 2, 3] }
  it_behaves_like "a collection"
end

Spectator.describe Hash do
  subject { {"a" => 1, "b" => 2} }
  it_behaves_like "a collection"
end

# Shared examples with parameters
Spectator.shared_examples "a mathematical operation" do |operation, a, b, expected|
  it "performs #{operation}" do
    result = subject.public_send(operation, a, b)
    expect(result).to eq(expected)
  end
end

Spectator.describe Calculator do
  subject { Calculator.new }
  
  include_examples "a mathematical operation", :add, 2, 3, 5
  include_examples "a mathematical operation", :multiply, 4, 5, 20
end
```

### Hooks

```crystal
Spectator.describe DatabaseTests do
  before_all do
    # Setup database connection
    @database = Database.connect("test.db")
  end
  
  after_all do
    # Cleanup database
    @database.close
    File.delete("test.db")
  end
  
  before_each do
    # Clean database before each test
    @database.clear_all_tables
  end
  
  after_each do
    # Cleanup after each test
    # (optional, before_each usually handles this)
  end
  
  around_each do |example|
    # Wrap each test in transaction
    @database.transaction do |tx|
      example.run
      tx.rollback
    end
  end
  
  it "creates user" do
    user = User.create(name: "Test")
    expect(user.id).not_to be_nil
  end
end
```

## Mocking and Stubbing

Spectator provides powerful mocking capabilities:

```crystal
# Create a mock
Spectator.describe UserService do
  mock EmailService do
    stub send_welcome_email(user : User) : Bool
  end
  
  let(email_service) { mock(EmailService) }
  subject { UserService.new(email_service) }
  
  describe "#register_user" do
    let(user) { User.new("John", "john@example.com") }
    
    it "sends welcome email" do
      # Setup expectation
      allow(email_service).to receive(:send_welcome_email)
        .with(user)
        .and_return(true)
      
      # Execute
      result = subject.register_user(user)
      
      # Verify
      expect(result).to be_true
      expect(email_service).to have_received(:send_welcome_email).with(user)
    end
    
    context "when email fails" do
      it "handles failure gracefully" do
        allow(email_service).to receive(:send_welcome_email)
          .and_return(false)
        
        result = subject.register_user(user)
        expect(result).to be_false
      end
    end
  end
end

# Stub existing methods
Spectator.describe TimeService do
  describe "#current_time_string" do
    it "returns formatted time" do
      # Stub Time.local to return fixed time
      fixed_time = Time.local(2024, 1, 1, 12, 0, 0)
      allow(Time).to receive(:local).and_return(fixed_time)
      
      result = TimeService.current_time_string
      expect(result).to eq("2024-01-01 12:00:00")
    end
  end
end
```

## Parameterized Tests

```crystal
# Test multiple values
Spectator.describe MathUtils do
  describe "#factorial" do
    sample [
      {0, 1},
      {1, 1},
      {2, 2},
      {3, 6},
      {4, 24},
      {5, 120}
    ] do |input, expected|
      it "calculates factorial of #{input}" do
        expect(MathUtils.factorial(input)).to eq(expected)
      end
    end
  end
  
  describe "#prime?" do
    sample [2, 3, 5, 7, 11, 13, 17, 19] do |number|
      it "#{number} is prime" do
        expect(MathUtils.prime?(number)).to be_true
      end
    end
    
    sample [1, 4, 6, 8, 9, 10, 12, 15] do |number|
      it "#{number} is not prime" do
        expect(MathUtils.prime?(number)).to be_false
      end
    end
  end
end
```

## Testing Async Code

```crystal
Spectator.describe "Async operations" do
  describe "channel communication" do
    it "sends and receives messages" do
      channel = Channel(String).new
      received = nil
      
      spawn do
        received = channel.receive
      end
      
      spawn do
        channel.send("hello")
      end
      
      # Wait for async operations
      sleep 0.1
      
      expect(received).to eq("hello")
    end
  end
  
  describe "HTTP requests" do
    it "makes async requests" do
      responses = [] of String
      done = Channel(Nil).new
      
      3.times do |i|
        spawn do
          # Simulate HTTP request
          sleep 0.1
          responses << "Response #{i}"
          done.send(nil) if responses.size == 3
        end
      end
      
      # Wait for all requests
      done.receive
      
      expect(responses).to have(3).items
    end
  end
end
```

## Testing File I/O

```crystal
Spectator.describe FileProcessor do
  let(temp_file) { create_temp_file("test content") }
  
  after_each do
    File.delete(temp_file) if File.exists?(temp_file)
  end
  
  describe "#read_file" do
    it "reads file content" do
      content = FileProcessor.read_file(temp_file)
      expect(content).to eq("test content")
    end
  end
  
  describe "#process_file" do
    it "processes and saves file" do
      output_file = temp_file + ".processed"
      
      FileProcessor.process_file(temp_file, output_file)
      
      expect(File.exists?(output_file)).to be_true
      processed_content = File.read(output_file)
      expect(processed_content).to contain("processed")
      
      File.delete(output_file)
    end
  end
end
```

## Testing Error Conditions

```crystal
Spectator.describe ConfigParser do
  describe "#parse" do
    context "with valid config" do
      let(config_text) { "host=localhost\nport=8080" }
      
      it "parses successfully" do
        config = ConfigParser.parse(config_text)
        expect(config.host).to eq("localhost")
        expect(config.port).to eq(8080)
      end
    end
    
    context "with invalid config" do
      let(config_text) { "invalid format" }
      
      it "raises parse error" do
        expect { ConfigParser.parse(config_text) }
          .to raise_error(ConfigParser::ParseError, /invalid format/)
      end
    end
    
    context "with empty config" do
      let(config_text) { "" }
      
      it "returns default values" do
        config = ConfigParser.parse(config_text)
        expect(config.host).to eq("0.0.0.0")
        expect(config.port).to eq(3000)
      end
    end
  end
end
```

## Performance Testing

```crystal
require "benchmark"

Spectator.describe "Performance tests" do
  describe "large array processing" do
    let(large_array) { (1..100_000).to_a }
    
    it "processes array efficiently" do
      time = Benchmark.realtime do
        result = ArrayProcessor.process(large_array)
        expect(result.size).to eq(100_000)
      end
      
      # Should complete within 1 second
      expect(time).to be < 1.0
    end
  end
  
  describe "memory usage" do
    it "doesn't leak memory" do
      initial_memory = GC.stats.heap_size
      
      1000.times do
        ObjectFactory.create_and_process
      end
      
      GC.collect
      final_memory = GC.stats.heap_size
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be minimal
      expect(memory_growth).to be < 1_000_000  # 1MB
    end
  end
end
```

## Custom Matchers

```crystal
# Define custom matcher
module Spectator::Matchers
  def be_valid_email
    ValidEmailMatcher.new
  end
  
  struct ValidEmailMatcher < Matcher(String)
    def match(actual_value)
      email_regex = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
      actual_value.match(email_regex) != nil
    end
    
    def failure_message(actual_value)
      "#{actual_value} is not a valid email address"
    end
    
    def failure_message_when_negated(actual_value)
      "#{actual_value} is a valid email address"
    end
  end
end

# Use custom matcher
Spectator.describe "Email validation" do
  it "validates email format" do
    expect("user@example.com").to be_valid_email
    expect("invalid-email").not_to be_valid_email
  end
end
```

## Test Configuration

Create `spec/spec_helper.cr` with common configuration:

```crystal
require "spectator"

# Configure Spectator
Spectator.configure do |config|
  config.fail_fast = false
  config.randomize = true
  config.seed = 42  # For reproducible randomization
  config.profile = 10
  config.dry_run = false
end

# Helper methods
module TestHelpers
  def with_temp_directory(&block)
    dir = File.tempname("test")
    Dir.mkdir(dir)
    begin
      yield dir
    ensure
      FileUtils.rm_rf(dir)
    end
  end
  
  def capture_output(&block)
    old_stdout = STDOUT
    old_stderr = STDERR
    
    stdout = IO::Memory.new
    stderr = IO::Memory.new
    
    STDOUT = stdout
    STDERR = stderr
    
    begin
      yield
      {stdout.to_s, stderr.to_s}
    ensure
      STDOUT = old_stdout
      STDERR = old_stderr
    end
  end
end

Spectator.configure do |config|
  config.include TestHelpers
end
```

## Running Tests

```bash
# Run all tests
crystal spec

# Run specific file
crystal spec spec/models/user_spec.cr

# Run with specific tag
crystal spec --tag unit

# Run with verbose output
crystal spec --verbose

# Run in parallel (with preview_mt)
crystal spec -Dpreview_mt --parallel

# Generate coverage report (if available)
crystal spec --coverage

# Run with profiling
crystal spec --profile
```

## Best Practices

1. **Use descriptive test names**: Test behavior, not implementation
2. **Follow AAA pattern**: Arrange, Act, Assert
3. **Keep tests independent**: Each test should work in isolation
4. **Use let for setup**: Lazy evaluation and better performance
5. **Test edge cases**: Nil values, empty collections, boundary conditions
6. **Mock external dependencies**: Don't rely on external services
7. **Test error conditions**: Ensure proper error handling
8. **Keep tests fast**: Avoid slow operations when possible
9. **Use shared examples**: Reduce duplication
10. **Test behavior, not implementation**: Focus on what, not how

Testing is crucial for the reliability of the MTProto implementation. Comprehensive tests help ensure protocol correctness and catch regressions early.

Next: [Best Practices](09-best-practices.md)