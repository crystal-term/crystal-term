# Crystal Standard Library

Crystal comes with a comprehensive standard library. This guide covers the most commonly used modules and classes.

## Core Types and Methods

### String

```crystal
# Creation
str = "Hello, World!"
multiline = <<-TEXT
  This is a
  multiline string
  TEXT
  
# Common operations
str.size              # => 13
str.upcase            # => "HELLO, WORLD!"
str.downcase          # => "hello, world!"
str.capitalize        # => "Hello, world!"
str.reverse           # => "!dlroW ,olleH"
str.strip             # Remove whitespace
str.chomp             # Remove trailing newline

# Checking content
str.empty?            # => false
str.blank?            # => false (empty or only whitespace)
str.includes?("World") # => true
str.starts_with?("Hello") # => true
str.ends_with?("!")   # => true

# Splitting and joining
words = "one,two,three".split(",")  # => ["one", "two", "three"]
words.join(" ")       # => "one two three"

# Pattern matching
"test@example.com".match(/(.+)@(.+)/)
$1  # => "test"
$2  # => "example.com"

# String interpolation
name = "Crystal"
"Hello, #{name}!"     # => "Hello, Crystal!"

# String building (efficient)
String.build do |io|
  io << "Hello"
  io << " "
  io << "World"
end  # => "Hello World"
```

### Numbers

```crystal
# Integer operations
42.even?              # => true
42.odd?               # => false
42.abs                # => 42
-42.abs               # => 42
10.gcd(15)            # => 5
2.lcm(3)              # => 6

# Conversions
"42".to_i             # => 42
"42".to_i?            # => 42 (nil if invalid)
42.to_s               # => "42"
42.to_s(16)           # => "2a" (hexadecimal)

# Float operations
3.14.round            # => 3
3.14.round(1)         # => 3.1
3.14.ceil             # => 4
3.14.floor            # => 3

# Math module
Math.sqrt(16)         # => 4.0
Math.sin(Math::PI/2)  # => 1.0
Math.log(Math::E)     # => 1.0
Math.exp(1)           # => 2.718...

# Random numbers
rand                  # => 0.0..1.0
rand(10)              # => 0..9
rand(5..10)           # => 5..10
Random.rand(100)      # Using specific Random instance
```

### Array

```crystal
# Creation
arr = [1, 2, 3]
empty = [] of Int32
mixed = [1, "two", 3.0]  # Array(Int32 | String | Float64)

# Access
arr[0]                # => 1
arr[-1]               # => 3 (last element)
arr[10]?              # => nil (safe access)
arr.first             # => 1
arr.last              # => 3

# Modification
arr << 4              # Append
arr.push(5)           # Same as <<
arr.unshift(0)        # Prepend
arr.insert(2, 999)    # Insert at index
arr.delete(999)       # Remove value
arr.delete_at(2)      # Remove at index

# Iteration
arr.each { |n| puts n }
arr.each_with_index { |n, i| puts "#{i}: #{n}" }
arr.map { |n| n * 2 } # => [2, 4, 6]
arr.select(&.even?)   # => [2]
arr.reject(&.even?)   # => [1, 3]

# Searching
arr.includes?(2)      # => true
arr.index(2)          # => 1
arr.find { |n| n > 2 } # => 3

# Aggregation
[1, 2, 3].sum         # => 6
[1, 2, 3].product     # => 6
[1, 2, 3].min         # => 1
[1, 2, 3].max         # => 3

# Transformation
[1, 2, 3].reverse     # => [3, 2, 1]
[3, 1, 2].sort        # => [1, 2, 3]
[1, 2, 2, 3].uniq     # => [1, 2, 3]
[[1, 2], [3, 4]].flatten # => [1, 2, 3, 4]

# Sampling
[1, 2, 3, 4, 5].sample    # Random element
[1, 2, 3, 4, 5].sample(2) # Random 2 elements
```

### Hash

```crystal
# Creation
hash = {"a" => 1, "b" => 2}
empty = {} of String => Int32
symbols = {:a => 1, :b => 2}  # Hash(Symbol, Int32)

# Access
hash["a"]             # => 1
hash["z"]?            # => nil (safe access)
hash.fetch("z", 0)    # => 0 (with default)

# Modification
hash["c"] = 3
hash.delete("a")
hash.clear

# Iteration
hash.each do |key, value|
  puts "#{key}: #{value}"
end

hash.keys             # => ["a", "b"]
hash.values           # => [1, 2]

# Transformation
hash.transform_keys(&.upcase)   # => {"A" => 1, "B" => 2}
hash.transform_values(&.*(2))   # => {"a" => 2, "b" => 4}
hash.select { |k, v| v > 1 }    # => {"b" => 2}
hash.reject { |k, v| v > 1 }    # => {"a" => 1}

# Merging
h1 = {"a" => 1, "b" => 2}
h2 = {"b" => 3, "c" => 4}
h1.merge(h2)          # => {"a" => 1, "b" => 3, "c" => 4}
```

### Range

```crystal
# Inclusive range
(1..5).to_a           # => [1, 2, 3, 4, 5]
(1..5).includes?(3)   # => true
(1..5).sum            # => 15

# Exclusive range
(1...5).to_a          # => [1, 2, 3, 4]
(1...5).includes?(5)  # => false

# Character ranges
('a'..'z').includes?('m')  # => true

# Iteration
(1..3).each { |n| puts n }

# Sampling
(1..100).sample       # Random number in range
```

### Time

```crystal
# Current time
now = Time.local
utc = Time.utc

# Creating specific times
time = Time.local(2024, 12, 25, 10, 30, 45)
parsed = Time.parse("2024-12-25 10:30:45", "%Y-%m-%d %H:%M:%S", Time::Location.local)

# Time components
time.year             # => 2024
time.month            # => 12
time.day              # => 25
time.hour             # => 10
time.minute           # => 30
time.second           # => 45

# Day queries
time.monday?
time.weekend?

# Arithmetic
tomorrow = Time.local + 1.day
last_week = Time.local - 1.week
duration = Time.local - time  # Time::Span

# Formatting
time.to_s("%Y-%m-%d")        # => "2024-12-25"
time.to_s("%H:%M:%S")        # => "10:30:45"
time.to_unix                 # Unix timestamp
time.to_unix_ms              # Milliseconds

# Time zones
tokyo = Time.local(location: Time::Location.load("Asia/Tokyo"))
```

## I/O and Files

### File Operations

```crystal
# Reading files
content = File.read("file.txt")
lines = File.read_lines("file.txt")

# Writing files
File.write("output.txt", "Hello, World!")

# Appending
File.open("log.txt", "a") do |file|
  file.puts "Log entry"
end

# Check existence
File.exists?("file.txt")
File.file?("file.txt")
File.directory?("folder")

# File info
info = File.info("file.txt")
info.size
info.modification_time
info.permissions

# Working with paths
File.basename("/path/to/file.txt")    # => "file.txt"
File.dirname("/path/to/file.txt")     # => "/path/to"
File.extname("file.txt")              # => ".txt"
File.join("path", "to", "file.txt")   # => "path/to/file.txt"

# Directory operations
Dir.mkdir("new_folder")
Dir.entries(".")                      # List directory contents
Dir.glob("*.txt")                     # Find matching files

# Temporary files
File.tempfile("prefix") do |file|
  file.print("temporary data")
  # File is deleted after block
end
```

### IO Operations

```crystal
# Reading from IO
io = IO::Memory.new("Hello\nWorld")
io.gets               # => "Hello"
io.read_char          # => 'W'
io.read_byte          # => 111 (o)

# Writing to IO
io = IO::Memory.new
io.print("Hello")
io.puts(" World")     # Adds newline
io.write_bytes(42, IO::ByteFormat::LittleEndian)

# Working with STDIN/STDOUT
puts "Enter name:"
name = gets           # Read from STDIN
STDERR.puts "Error!"  # Write to STDERR

# Binary data
bytes = Bytes.new(4)
bytes[0] = 0xFF_u8
File.write("binary.dat", bytes)

# Encoding
io = IO::Memory.new
io.set_encoding("UTF-8")
```

## JSON and YAML

### JSON

```crystal
require "json"

# Parsing
json_str = %({"name": "Crystal", "version": 1.0})
data = JSON.parse(json_str)
data["name"]          # => "Crystal"

# Type-safe parsing
class Package
  include JSON::Serializable
  
  property name : String
  property version : Float64
  property? beta : Bool = false
end

package = Package.from_json(json_str)
package.name          # => "Crystal"

# Generating JSON
hash = {"name" => "Crystal", "awesome" => true}
hash.to_json          # => {"name":"Crystal","awesome":true}

# Pretty printing
hash.to_pretty_json   # Formatted with indentation

# JSON mapping with custom names
class User
  include JSON::Serializable
  
  @[JSON::Field(key: "full_name")]
  property name : String
  
  @[JSON::Field(ignore: true)]
  property password : String?
end
```

### YAML

```crystal
require "yaml"

# Parsing
yaml_str = <<-YAML
name: Crystal
features:
  - Fast
  - Type-safe
  - Productive
YAML

data = YAML.parse(yaml_str)

# Type-safe parsing
class Config
  include YAML::Serializable
  
  property name : String
  property features : Array(String)
end

config = Config.from_yaml(yaml_str)

# Generating YAML
{"name" => "Crystal", "version" => 1.0}.to_yaml
```

## HTTP Client

```crystal
require "http/client"

# Simple GET request
response = HTTP::Client.get("https://api.example.com/data")
response.status_code  # => 200
response.body         # Response content

# POST with JSON
response = HTTP::Client.post(
  "https://api.example.com/users",
  headers: HTTP::Headers{"Content-Type" => "application/json"},
  body: {"name" => "John"}.to_json
)

# Using client instance
client = HTTP::Client.new("api.example.com", tls: true)
client.basic_auth("user", "pass")

response = client.get("/users", headers: HTTP::Headers{
  "Accept" => "application/json"
})

# Handling responses
if response.success?
  data = JSON.parse(response.body)
else
  puts "Error: #{response.status_code}"
end

# Form data
form = HTTP::Params.build do |params|
  params.add "name", "John"
  params.add "email", "john@example.com"
end

HTTP::Client.post("https://example.com/form", form: form)

# Following redirects
response = HTTP::Client.get("http://example.com") do |response|
  # Handle redirects manually
end
```

## Regular Expressions

```crystal
# Basic matching
"Crystal 1.0" =~ /\d+\.\d+/     # => 8 (match position)
"Crystal" =~ /Ruby/             # => nil

# Capture groups
match = "test@example.com".match(/(.+)@(.+)\.(.+)/)
match[0]              # => "test@example.com" (full match)
match[1]              # => "test"
match[2]              # => "example"
match[3]              # => "com"

# Named groups
match = "John:30".match(/(?<name>\w+):(?<age>\d+)/)
match["name"]         # => "John"
match["age"]          # => "30"

# Global matching
"a1b2c3".scan(/\d/) do |match|
  puts match[0]       # Prints: 1, 2, 3
end

# Substitution
"Hello World".gsub(/[aeiou]/, "*")     # => "H*ll* W*rld"
"Hello World".gsub(/(\w+)/) { |m| m[0].upcase }  # => "HELLO WORLD"

# Regex options
/crystal/i            # Case insensitive
/crystal/m            # Multiline mode
/crystal/x            # Extended mode (ignore whitespace)

# Common patterns
email = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
url = /https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&\/\/=]*)/
```

## Encoding and Crypto

### Base64

```crystal
require "base64"

# Encoding
encoded = Base64.encode("Hello, Crystal!")
# => "SGVsbG8sIENyeXN0YWwh"

# Decoding
decoded = Base64.decode_string(encoded)
# => "Hello, Crystal!"

# URL-safe encoding
Base64.urlsafe_encode("data", padding: false)
```

### Digest

```crystal
require "digest"

# SHA256
sha = Digest::SHA256.hexdigest("password")
# => "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"

# MD5
md5 = Digest::MD5.hexdigest("data")

# HMAC
require "openssl/hmac"
hmac = OpenSSL::HMAC.hexdigest(
  OpenSSL::Algorithm::SHA256,
  "secret_key",
  "message"
)
```

## Process and System

```crystal
# Execute commands
output = `ls -la`
success = system("echo Hello")

# Process with options
process = Process.new(
  "grep",
  args: ["pattern", "file.txt"],
  output: Process::Redirect::Pipe,
  error: Process::Redirect::Pipe
)

output = process.output.gets_to_end
error = process.error.gets_to_end
process.wait

# Environment variables
ENV["PATH"]                    # Get
ENV["MY_VAR"] = "value"       # Set
ENV.has_key?("MY_VAR")        # Check

# Exit
exit(0)                       # Success
abort("Error message")        # Exit with error
```

## URI and Path

```crystal
require "uri"

# Parsing URLs
uri = URI.parse("https://user:pass@example.com:8080/path?q=crystal#section")
uri.scheme            # => "https"
uri.host              # => "example.com"
uri.port              # => 8080
uri.path              # => "/path"
uri.query             # => "q=crystal"
uri.fragment          # => "section"

# Building URLs
uri = URI.new(
  scheme: "https",
  host: "api.example.com",
  path: "/v1/users",
  query: "page=1&limit=10"
)

# Path manipulation
require "path"

path = Path["path/to/file.txt"]
path.parent           # => Path["path/to"]
path.basename         # => "file.txt"
path.extension        # => ".txt"
path.join("other")    # => Path["path/to/file.txt/other"]
```

## Useful Utilities

### Logger

```crystal
require "log"

# Basic logging
Log.info { "Application started" }
Log.warn { "This is a warning" }
Log.error { "An error occurred" }

# Custom logger
log = Log.for("myapp")
log.level = Log::Severity::Debug
log.debug { "Debug information" }

# Structured logging
Log.info { {user_id: 123, action: "login"} }
```

### OptionParser

```crystal
require "option_parser"

verbose = false
name = "World"

OptionParser.parse do |parser|
  parser.banner = "Usage: app [options]"
  
  parser.on("-v", "--verbose", "Enable verbose output") do
    verbose = true
  end
  
  parser.on("-n NAME", "--name=NAME", "Name to greet") do |n|
    name = n
  end
  
  parser.on("-h", "--help", "Show help") do
    puts parser
    exit
  end
end

puts "Hello, #{name}!"
puts "Verbose mode enabled" if verbose
```

### CSV

```crystal
require "csv"

# Reading CSV
CSV.each_row(File.open("data.csv")) do |row|
  puts row[0]  # First column
end

# Writing CSV
CSV.build do |csv|
  csv.row ["Name", "Age", "City"]
  csv.row ["John", 30, "New York"]
  csv.row ["Jane", 25, "London"]
end

# Parsing with headers
csv = CSV.new(data, headers: true)
csv.each do |row|
  puts row["Name"]
end
```

## Best Practices

1. **Use built-in methods**: Crystal's stdlib is comprehensive
2. **Prefer type-safe parsing**: Use `JSON::Serializable` over `JSON.parse`
3. **Handle errors properly**: Many methods have `?` variants that return nil
4. **Use blocks for resources**: Files, HTTP clients auto-close with blocks
5. **Check the API docs**: [crystal-lang.org/api](https://crystal-lang.org/api)

The Crystal standard library provides a solid foundation for most applications. For additional functionality, explore the Crystal shards ecosystem at [shardbox.org](https://shardbox.org).

Next: [Performance and Memory](06-performance.md)