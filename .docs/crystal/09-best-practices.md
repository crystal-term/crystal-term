# Crystal Best Practices and Idioms

This guide covers best practices, idioms, and patterns for writing idiomatic Crystal code, especially for complex projects like MTProto implementations.

## Code Organization

### Project Structure

```
src/
  tektite/
    client/           # High-level client API
    rpc/             # RPC handling
    session/         # Session management  
    transport/       # Protocol transports
    crypto/          # Cryptographic operations
    schema/          # TL schema definitions
    errors.cr        # Custom exceptions
    version.cr       # Version information
  tektite.cr         # Main module file
spec/
  tektite/          # Mirror src structure
    client_spec.cr
    rpc_spec.cr
    # ...
  spec_helper.cr    # Test configuration
shard.yml           # Dependencies
README.md
CHANGELOG.md
```

### Module Organization

```crystal
# Prefer modules for namespacing
module Tektite
  module Transport
    abstract class Base
      abstract def connect
      abstract def send_data(data : Bytes)
      abstract def receive_data : Bytes
    end
    
    class TCP < Base
      # Implementation
    end
    
    class TLS < Base
      # Implementation
    end
  end
end

# Use nested modules for logical grouping
module Tektite
  module Schema
    module Types
      # TL type definitions
    end
    
    module Methods
      # TL method definitions
    end
  end
end
```

## Type Safety

### Explicit Type Annotations

```crystal
# Good - clear intent
class Session
  @auth_key : Bytes?
  @server_salt : UInt64?
  @sequence : Int32 = 0
  
  def initialize(@data_center : Int32)
  end
  
  def authenticated? : Bool
    !@auth_key.nil?
  end
end

# Use union types for multiple valid types
alias MessageId = Int64
alias UserId = Int64
alias ChatId = Int64

# For complex types, use type aliases
alias TLObject = Hash(String, JSON::Any)
alias AuthResult = {auth_key: Bytes, server_salt: UInt64}
```

### Nil Safety

```crystal
# Handle nil explicitly
def find_user(id : UserId) : User?
  users[id]?
end

# Use safe navigation
user = find_user(123)
name = user.try(&.name) || "Unknown"

# Use if expressions for nil checks
if user = find_user(123)
  puts "Found user: #{user.name}"
else
  puts "User not found"
end

# Avoid not_nil! unless you're certain
# Bad
user = find_user(123).not_nil!

# Good
user = find_user(123)
return unless user
```

### Error Handling

```crystal
# Define specific error types
module Tektite
  class Error < Exception; end
  
  class AuthenticationError < Error; end
  class NetworkError < Error; end
  class ProtocolError < Error; end
  
  class FloodWaitError < Error
    getter seconds : Int32
    
    def initialize(@seconds : Int32)
      super("Must wait #{@seconds} seconds")
    end
  end
end

# Use result types for operations that might fail
alias Result(T) = T | Error

def parse_message(data : Bytes) : Result(Message)
  return ProtocolError.new("Invalid length") if data.size < 4
  
  begin
    Message.from_bytes(data)
  rescue ex
    ProtocolError.new("Parse failed: #{ex.message}")
  end
end

# Handle errors at appropriate levels
begin
  message = parse_message(data)
  case message
  when Message
    process_message(message)
  when Error
    log.error("Failed to parse message: #{message.message}")
  end
rescue ex : NetworkError
  reconnect
rescue ex : AuthenticationError
  authenticate
end
```

## Performance Guidelines

### Memory Efficiency

```crystal
# Use structs for small, immutable data
struct Point
  getter x : Float64
  getter y : Float64
  
  def initialize(@x : Float64, @y : Float64)
  end
end

# Use Bytes instead of Array(UInt8) for binary data
def encrypt_data(data : Bytes, key : Bytes) : Bytes
  # Implementation
end

# Pre-allocate collections when size is known
def process_batch(size : Int32)
  results = Array(Result).new(size)
  size.times do |i|
    results << process_item(i)
  end
  results
end

# Use string building for concatenation
def build_query(parts : Array(String)) : String
  String.build do |io|
    parts.each_with_index do |part, i|
      io << " AND " if i > 0
      io << part
    end
  end
end
```

### Efficient Iterations

```crystal
# Use each instead of manual loops
# Bad
i = 0
while i < array.size
  process(array[i])
  i += 1
end

# Good
array.each { |item| process(item) }

# Use appropriate enumerable methods
# Instead of
results = [] of Result
array.each do |item|
  if item.valid?
    results << transform(item)
  end
end

# Use
results = array.select(&.valid?).map { |item| transform(item) }

# For single pass operations
sum = array.sum { |item| item.valid? ? item.value : 0 }
```

### Binary Protocol Handling

```crystal
# Efficient binary reading
class BinaryReader
  def initialize(@io : IO)
    @buffer = Bytes.new(8)  # Reuse buffer
  end
  
  def read_uint32 : UInt32
    @io.read_fully(@buffer[0, 4])
    IO::ByteFormat::LittleEndian.decode(UInt32, @buffer)
  end
  
  def read_bytes(size : Int32) : Bytes
    bytes = Bytes.new(size)
    @io.read_fully(bytes)
    bytes
  end
end

# Use IO::Memory for building binary data
def serialize_message(message : Message) : Bytes
  io = IO::Memory.new
  io.write_bytes(message.id, IO::ByteFormat::LittleEndian)
  io.write_bytes(message.data.size, IO::ByteFormat::LittleEndian)
  io.write(message.data)
  io.to_slice
end
```

## Error Handling Patterns

### Defensive Programming

```crystal
# Validate inputs
def send_message(text : String, chat_id : ChatId)
  raise ArgumentError.new("Text cannot be empty") if text.empty?
  raise ArgumentError.new("Invalid chat ID") if chat_id <= 0
  
  # Implementation
end

# Use preconditions
def decrypt_message(encrypted : Bytes, key : Bytes)
  raise ArgumentError.new("Key must be 32 bytes") if key.size != 32
  raise ArgumentError.new("Encrypted data too short") if encrypted.size < 16
  
  # Implementation
end

# Check state before operations
def send_request(request : Request)
  raise "Not connected" unless connected?
  raise "Not authenticated" unless authenticated?
  
  # Implementation
end
```

### Resource Management

```crystal
# Use blocks for automatic cleanup
def with_connection(&block : Connection ->)
  conn = Connection.new
  begin
    conn.connect
    yield conn
  ensure
    conn.close
  end
end

# RAII pattern with finalize
class FileManager
  def initialize(@path : String)
    @file = File.open(@path, "w")
  end
  
  def write(data : String)
    @file.print(data)
  end
  
  def finalize
    @file.close if @file
  end
end
```

## Concurrency Best Practices

### Channel Usage

```crystal
# Prefer channels over shared state
class MessageProcessor
  def initialize
    @input = Channel(Message).new
    @output = Channel(ProcessedMessage).new
    spawn_processor
  end
  
  private def spawn_processor
    spawn do
      @input.each do |message|
        processed = process(message)
        @output.send(processed)
      end
    end
  end
  
  def process_message(message : Message)
    @input.send(message)
  end
  
  def get_result : ProcessedMessage
    @output.receive
  end
end

# Use select for multiple channels
def handle_events(message_ch, error_ch, timeout_ch)
  loop do
    select
    when message = message_ch.receive
      handle_message(message)
    when error = error_ch.receive
      handle_error(error)
    when timeout_ch.receive
      handle_timeout
      break
    end
  end
end
```

### Fiber Management

```crystal
# Name fibers for debugging
spawn(name: "message-processor") do
  process_messages
end

# Use supervision patterns
class Supervisor
  def initialize(@worker_count : Int32)
    @workers = Array(Fiber).new(@worker_count)
    start_workers
  end
  
  private def start_workers
    @worker_count.times do |i|
      @workers[i] = spawn(name: "worker-#{i}") do
        worker_loop
      end
    end
  end
  
  def restart_worker(index : Int32)
    @workers[index] = spawn(name: "worker-#{index}") do
      worker_loop
    end
  end
end
```

## API Design

### Method Signatures

```crystal
# Use named arguments for clarity
def create_message(
  *,
  text : String,
  chat_id : ChatId,
  reply_to : MessageId? = nil,
  disable_preview : Bool = false
)
  # Implementation
end

# Builder pattern for complex objects
class RequestBuilder
  def initialize
    @params = Hash(String, String | Int32 | Bool).new
  end
  
  def with_text(text : String) : self
    @params["text"] = text
    self
  end
  
  def with_chat_id(id : ChatId) : self
    @params["chat_id"] = id
    self
  end
  
  def build : Request
    Request.new(@params)
  end
end

# Fluent interfaces
message = RequestBuilder.new
  .with_text("Hello")
  .with_chat_id(123)
  .build
```

### Documentation

```crystal
# Document public APIs thoroughly
module Tektite
  # A client for interacting with the Telegram MTProto API.
  #
  # The client handles authentication, connection management,
  # and provides a high-level interface for API calls.
  #
  # ## Example
  #
  # ```
  # client = Client.new(api_id: 123, api_hash: "abc")
  # client.connect
  # client.sign_in(phone: "+1234567890")
  # ```
  class Client
    # Sends a text message to a chat.
    #
    # *text* - The message text to send
    # *chat_id* - The chat identifier  
    # *reply_to* - Optional message ID to reply to
    #
    # Returns the sent message or raises an error.
    #
    # ```
    # message = client.send_message(
    #   text: "Hello!",
    #   chat_id: 123
    # )
    # ```
    def send_message(
      *,
      text : String,
      chat_id : ChatId,
      reply_to : MessageId? = nil
    ) : Message
      # Implementation
    end
  end
end
```

## Configuration and Settings

```crystal
# Use structs for configuration
struct Config
  getter api_id : Int32
  getter api_hash : String
  getter data_center : Int32
  getter timeout : Time::Span
  getter retry_attempts : Int32
  
  def initialize(
    @api_id : Int32,
    @api_hash : String,
    @data_center : Int32 = 2,
    @timeout : Time::Span = 30.seconds,
    @retry_attempts : Int32 = 3
  )
  end
  
  # Validation in constructor
  def initialize(
    api_id : Int32,
    api_hash : String,
    **options
  )
    raise ArgumentError.new("API ID must be positive") if api_id <= 0
    raise ArgumentError.new("API hash cannot be empty") if api_hash.empty?
    
    initialize(api_id, api_hash, **options)
  end
end

# Builder for complex configuration
class ConfigBuilder
  def self.from_env : Config
    Config.new(
      api_id: ENV["TELEGRAM_API_ID"].to_i,
      api_hash: ENV["TELEGRAM_API_HASH"],
      data_center: ENV.fetch("TELEGRAM_DC", "2").to_i
    )
  end
  
  def self.from_file(path : String) : Config
    data = YAML.parse(File.read(path))
    Config.new(
      api_id: data["api_id"].as_i,
      api_hash: data["api_hash"].as_s,
      data_center: data["data_center"]?.try(&.as_i) || 2
    )
  end
end
```

## Testing Strategies

### Test Organization

```crystal
# Test behavior, not implementation
Spectator.describe Client do
  describe "#send_message" do
    context "with valid parameters" do
      it "sends message successfully" do
        # Test the outcome, not the internal calls
      end
    end
    
    context "when not authenticated" do
      it "raises authentication error" do
        # Test error conditions
      end
    end
  end
end

# Use factories for test data
module Factories
  def build_user(
    id : UserId = 123,
    name : String = "Test User",
    **options
  )
    User.new(id: id, name: name, **options)
  end
  
  def build_message(
    id : MessageId = 456,
    text : String = "Test message",
    user : User = build_user,
    **options
  )
    Message.new(id: id, text: text, user: user, **options)
  end
end
```

### Mocking External Dependencies

```crystal
# Abstract external dependencies
abstract class NetworkInterface
  abstract def send_request(data : Bytes) : Bytes
  abstract def connect(host : String, port : Int32)
end

class TcpNetwork < NetworkInterface
  # Real implementation
end

# Mock for testing
mock MockNetwork < NetworkInterface do
  stub send_request(data : Bytes) : Bytes
  stub connect(host : String, port : Int32)
end

# Dependency injection
class Client
  def initialize(@network : NetworkInterface)
  end
end
```

## Debugging and Logging

```crystal
# Use structured logging
require "log"

Log.setup do |config|
  config.bind("tektite.*", Log::Severity::Debug, Log::IOBackend.new)
end

class Client
  private LOG = Log.for(self)
  
  def send_message(text : String, chat_id : ChatId)
    LOG.debug { "Sending message to chat #{chat_id}" }
    
    begin
      result = api_call("sendMessage", {
        text: text,
        chat_id: chat_id
      })
      
      LOG.info { "Message sent successfully" }
      result
    rescue ex
      LOG.error(exception: ex) { "Failed to send message" }
      raise
    end
  end
end
```

## Code Style

### Crystal Conventions

```crystal
# Use snake_case for methods and variables
def send_message; end
def user_name; end

# Use PascalCase for types
class MessageProcessor; end
struct UserInfo; end
enum ConnectionState; end

# Use SCREAMING_SNAKE_CASE for constants
MAX_RETRIES = 3
DEFAULT_TIMEOUT = 30.seconds

# Use descriptive names
# Bad
def proc(d)
  # ...
end

# Good
def process_message(data : Bytes)
  # ...
end

# Use verbs for methods that do something
def calculate_hash; end
def send_request; end
def validate_input; end

# Use nouns/adjectives for methods that return state
def authenticated?; end
def message_count; end
def current_user; end
```

### Method Design

```crystal
# Keep methods focused and small
# Bad
def handle_message(message)
  # 50 lines of mixed responsibilities
end

# Good
def handle_message(message : Message)
  validate_message(message)
  process_content(message)
  store_message(message)
  notify_listeners(message)
end

# Use early returns to reduce nesting
def process_user(user : User?)
  return unless user
  return unless user.active?
  return unless user.verified?
  
  perform_processing(user)
end

# Prefer composition over inheritance
class MessageHandler
  def initialize(@validator : MessageValidator, @processor : MessageProcessor)
  end
  
  def handle(message : Message)
    return unless @validator.valid?(message)
    @processor.process(message)
  end
end
```

## Common Antipatterns to Avoid

```crystal
# Don't use exceptions for control flow
# Bad
def find_user(id)
  user = users[id]
  raise "Not found" unless user
  user
end

# Good
def find_user(id) : User?
  users[id]?
end

# Don't ignore return values
# Bad
send_message(text, chat_id)  # Ignoring result

# Good
result = send_message(text, chat_id)
case result
when Message
  puts "Sent: #{result.id}"
when Error
  puts "Failed: #{result.message}"
end

# Don't use global state
# Bad
$current_user = user

# Good - pass as parameter or use dependency injection
class Service
  def initialize(@current_user : User)
  end
end

# Don't catch all exceptions blindly
# Bad
begin
  risky_operation
rescue
  # Silent failure
end

# Good
begin
  risky_operation
rescue TimeoutError
  retry_with_backoff
rescue NetworkError => ex
  log.error("Network error: #{ex.message}")
  raise
end
```

Following these best practices helps create maintainable, performant, and reliable Crystal code. They're especially important for complex projects like MTProto implementations where correctness and performance are critical.

Next: [Common Pitfalls](10-common-pitfalls.md)