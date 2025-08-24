# Crystal Language Fundamentals

## Basic Syntax

Crystal's syntax is heavily inspired by Ruby, making it familiar to Ruby developers. However, it's a compiled, statically-typed language with some important differences.

### Comments

```crystal
# Single line comment

# Crystal supports documentation comments
# that start with a single hash

# TODO: This is a TODO comment
# FIXME: This is a FIXME comment
# NOTE: This is a NOTE comment
```

### Variables and Constants

```crystal
# Local variables (lowercase or underscore)
name = "Crystal"
_private = 42

# Constants (uppercase)
VERSION = "1.0.0"
MAX_SIZE = 1024

# Instance variables (start with @)
@name = "John"

# Class variables (start with @@)
@@count = 0
```

### Basic Data Types

```crystal
# Nil
nothing = nil

# Boolean
active = true
disabled = false

# Numbers
integer = 42                    # Int32
big_int = 9223372036854775807  # Int64
negative = -42                  # Int32
hex = 0xFF                      # 255
binary = 0b1010                 # 10
octal = 0o755                   # 493

float = 3.14                    # Float64
float32 = 3.14_f32             # Float32
scientific = 1.0e-8            # Float64

# Characters
char = 'a'                      # Char
unicode_char = '♥'              # Char

# Strings
string = "Hello, Crystal!"
multiline = "This is
a multiline
string"
interpolated = "1 + 1 = #{1 + 1}"

# Symbols (compile-time strings)
symbol = :crystal
another = :"symbol with spaces"

# Arrays
array = [1, 2, 3]               # Array(Int32)
mixed = [1, "two", 3.0]         # Array(Int32 | String | Float64)
typed_array = [] of String      # Array(String)

# Hashes
hash = {"a" => 1, "b" => 2}     # Hash(String, Int32)
symbol_hash = {a: 1, b: 2}      # NamedTuple(a: Int32, b: Int32)
typed_hash = {} of String => Int32  # Hash(String, Int32)

# Ranges
inclusive = 1..10               # Range(Int32, Int32)
exclusive = 1...10              # Range(Int32, Int32)

# Tuples (fixed-size, immutable)
tuple = {1, "hello", true}      # Tuple(Int32, String, Bool)
named = {name: "John", age: 30} # NamedTuple(name: String, age: Int32)

# Regular Expressions
regex = /hello/i                # Case insensitive
pattern = %r{^/users/(\d+)$}    # Alternative syntax
```

## Control Flow

### If/Unless

```crystal
# If statement
if age >= 18
  puts "Adult"
elsif age >= 13
  puts "Teenager"
else
  puts "Child"
end

# Unless (negative if)
unless name.empty?
  puts "Hello, #{name}"
end

# Ternary operator
status = active ? "on" : "off"

# Suffix if/unless
puts "Hello" if greeting_enabled
exit unless authorized
```

### Case

```crystal
# Basic case
case language
when "Ruby"
  puts "Dynamic"
when "Crystal"
  puts "Static with inference"
when "C", "C++"
  puts "Manual memory management"
else
  puts "Unknown"
end

# Case with types
case value
when String
  puts "It's a string: #{value}"
when Int32
  puts "It's an integer: #{value}"
when Float64
  puts "It's a float: #{value}"
end

# Case with ranges
case score
when 90..100
  grade = "A"
when 80...90
  grade = "B"
when 70...80
  grade = "C"
else
  grade = "F"
end
```

### Loops

```crystal
# While loop
i = 0
while i < 10
  puts i
  i += 1
end

# Until loop
until i == 0
  i -= 1
  puts i
end

# Loop with break
loop do
  input = gets
  break if input == "quit"
  puts "You said: #{input}"
end

# Times
10.times do |i|
  puts i
end

# Each
[1, 2, 3].each do |n|
  puts n * 2
end

# Range iteration
(1..5).each do |i|
  puts i
end

# Each with index
["a", "b", "c"].each_with_index do |char, i|
  puts "#{i}: #{char}"
end
```

## Methods

### Basic Methods

```crystal
# Simple method
def greet
  puts "Hello!"
end

# Method with parameters
def greet(name)
  puts "Hello, #{name}!"
end

# Method with default parameter
def greet(name = "World")
  puts "Hello, #{name}!"
end

# Method with return value
def add(a, b)
  a + b  # Last expression is returned
end

# Explicit return
def check_age(age)
  return "Too young" if age < 18
  "OK"
end
```

### Type Restrictions

```crystal
# Parameter type restriction
def add(a : Int32, b : Int32)
  a + b
end

# Return type restriction
def divide(a : Float64, b : Float64) : Float64
  a / b
end

# Union types
def process(value : String | Int32)
  case value
  when String
    value.upcase
  when Int32
    value * 2
  end
end

# Nilable types
def find_user(id : Int32) : User?
  # Returns User or nil
  users[id]?
end
```

### Named Arguments

```crystal
# Method with named arguments
def create_user(name : String, age : Int32, admin : Bool = false)
  {name: name, age: age, admin: admin}
end

# Calling with named arguments
create_user(name: "John", age: 30)
create_user(age: 25, name: "Jane", admin: true)

# Required named arguments
def configure(*, host : String, port : Int32)
  "#{host}:#{port}"
end

configure(host: "localhost", port: 8080)
```

### Splats

```crystal
# Splat parameter (variable arguments)
def sum(*numbers)
  numbers.sum
end

sum(1, 2, 3, 4, 5)  # => 15

# Double splat (keyword arguments)
def configure(**options)
  options.each do |key, value|
    puts "#{key}: #{value}"
  end
end

configure(host: "localhost", port: 8080, ssl: true)
```

### Blocks and Yield

```crystal
# Method that yields
def twice
  yield
  yield
end

twice { puts "Hello" }

# Yield with value
def each_pair(array)
  i = 0
  while i < array.size - 1
    yield array[i], array[i + 1]
    i += 2
  end
end

each_pair([1, 2, 3, 4]) do |a, b|
  puts "#{a}, #{b}"
end

# Capture block
def measure(&block)
  start = Time.monotonic
  result = block.call
  elapsed = Time.monotonic - start
  {result: result, time: elapsed}
end

result = measure { sleep 1; 42 }
```

## Classes and Objects

### Basic Classes

```crystal
class Person
  # Constructor
  def initialize(@name : String, @age : Int32)
  end

  # Getter method
  def name
    @name
  end

  # Setter method
  def age=(value : Int32)
    @age = value
  end

  # Instance method
  def greet
    "Hello, I'm #{@name}"
  end

  # Class method
  def self.species
    "Homo sapiens"
  end
end

# Creating instances
person = Person.new("Alice", 30)
puts person.greet
puts Person.species
```

### Properties and Accessors

```crystal
class User
  # Generates getter and setter
  property name : String

  # Generates only getter
  getter email : String

  # Generates only setter
  setter password : String

  # Nilable property
  property? admin : Bool = false

  def initialize(@name : String, @email : String)
    @password = ""
  end
end
```

### Inheritance

```crystal
class Animal
  def initialize(@name : String)
  end

  def speak
    "..."
  end
end

class Dog < Animal
  def speak
    "#{@name} says Woof!"
  end

  def fetch
    "#{@name} fetches the ball"
  end
end

class Cat < Animal
  def speak
    "#{@name} says Meow!"
  end
end
```

### Abstract Classes and Methods

```crystal
abstract class Shape
  abstract def area : Float64
  abstract def perimeter : Float64

  def describe
    "Area: #{area}, Perimeter: #{perimeter}"
  end
end

class Rectangle < Shape
  def initialize(@width : Float64, @height : Float64)
  end

  def area : Float64
    @width * @height
  end

  def perimeter : Float64
    2 * (@width + @height)
  end
end
```

## Modules

```crystal
# Module as namespace
module Math
  PI = 3.14159265359

  def self.circle_area(radius)
    PI * radius ** 2
  end
end

puts Math::PI
puts Math.circle_area(5)

# Module as mixin
module Printable
  def print
    puts to_s
  end

  def print_twice
    2.times { print }
  end
end

class Document
  include Printable

  def initialize(@content : String)
  end

  def to_s
    @content
  end
end

doc = Document.new("Hello")
doc.print_twice
```

## Structs

Structs are value types (passed by value, not reference) and are allocated on the stack:

```crystal
struct Point
  property x : Float64
  property y : Float64

  def initialize(@x : Float64, @y : Float64)
  end

  def distance_to(other : Point)
    Math.sqrt((other.x - x) ** 2 + (other.y - y) ** 2)
  end
end

# Structs are copied by value
p1 = Point.new(0, 0)
p2 = p1
p2.x = 10
puts p1.x  # => 0 (unchanged)
```

## Enums

```crystal
enum Status
  Pending
  Active
  Completed
  Cancelled
end

# Using enums
status = Status::Active

# Enums in case statements
case status
when Status::Pending
  puts "Waiting..."
when Status::Active
  puts "In progress"
when Status::Completed
  puts "Done!"
when Status::Cancelled
  puts "Cancelled"
end

# Enums with values
enum Color
  Red   = 1
  Green = 2
  Blue  = 4
end

# Flags enum
@[Flags]
enum Permission
  Read
  Write
  Execute
end

# Combining flags
perms = Permission::Read | Permission::Write
```

## Exception Handling

```crystal
# Basic exception handling
begin
  result = 10 / 0
rescue DivisionByZeroError
  puts "Cannot divide by zero!"
rescue ex : Exception
  puts "Error: #{ex.message}"
ensure
  puts "This always runs"
end

# Raising exceptions
def validate_age(age)
  raise ArgumentError.new("Age cannot be negative") if age < 0
  age
end

# Custom exceptions
class ValidationError < Exception
end

class EmailValidator
  def self.validate(email)
    unless email.includes?("@")
      raise ValidationError.new("Invalid email format")
    end
    true
  end
end

# Method that might raise
def risky_operation
  if rand < 0.5
    raise "Random failure"
  end
  "Success"
end

# Handling with specific rescue
begin
  result = risky_operation
  puts result
rescue ex : String
  puts "Failed with: #{ex}"
end
```

## Nil Handling

Crystal tracks nil at compile time:

```crystal
# Nilable types use ? suffix
name : String? = nil

# Checking for nil
if name
  # Compiler knows name is not nil here
  puts name.size
else
  puts "Name is nil"
end

# Using try (safe navigation)
puts name.try(&.upcase)  # Returns nil if name is nil

# Not nil assertion (dangerous!)
puts name.not_nil!.size  # Raises if name is nil

# Default values
puts name || "Unknown"

# Pattern matching with nil
case name
when String
  puts "Name is: #{name}"
when nil
  puts "No name"
end
```

## Type System Features

### Union Types

```crystal
# Variable can be one of multiple types
value : Int32 | String | Nil = 42

# Type narrowing
if value.is_a?(String)
  puts value.upcase
elsif value.is_a?(Int32)
  puts value * 2
else
  puts "Value is nil"
end

# Responding to methods
if value.responds_to?(:upcase)
  puts value.upcase
end
```

### Generics

```crystal
class Box(T)
  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

int_box = Box.new(42)           # Box(Int32)
string_box = Box.new("hello")   # Box(String)

# Generic methods
def swap(a : T, b : T) forall T
  {b, a}
end

# Generic constraints
def max(a : T, b : T) : T forall T
  a > b ? a : b
end
```

### Type Aliases

```crystal
# Simple alias
alias UserId = Int32
alias JsonValue = String | Int32 | Float64 | Bool | Nil | Array(JsonValue) | Hash(String, JsonValue)

# Using aliases
def get_user(id : UserId)
  # ...
end
```

## Next Steps

This covers the fundamental syntax and concepts of Crystal. Key things to remember:

1. Crystal is statically typed with type inference
2. Nil is tracked at compile time
3. No method_missing or runtime metaprogramming
4. Use macros for compile-time metaprogramming
5. Structs are value types, classes are reference types
6. Enums instead of symbols for type-safe constants

Continue with [Ruby to Crystal Migration Guide](02-ruby-to-crystal.md) for specific differences from Ruby.
