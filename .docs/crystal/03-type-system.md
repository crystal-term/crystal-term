# Crystal's Type System

Crystal features a powerful static type system with local type inference. Understanding the type system is crucial for writing efficient and safe Crystal code.

## Type Inference

Crystal can infer types in most cases, so explicit type annotations are often unnecessary.

### Basic Inference

```crystal
# Literals have known types
name = "Crystal"     # : String
age = 25            # : Int32
pi = 3.14           # : Float64
active = true       # : Bool

# From method returns
result = "hello".upcase  # : String
size = [1, 2, 3].size   # : Int32

# From operations
sum = 10 + 20           # : Int32
product = 2.5 * 4       # : Float64
```

### Instance Variable Inference

Crystal needs to know instance variable types. It uses several rules:

```crystal
class User
  # Rule 1: From literal assignment
  def initialize
    @id = 0                # @id : Int32
    @name = "Unknown"      # @name : String
  end
end

class Product
  # Rule 2: From new calls
  def initialize
    @tags = Array(String).new  # @tags : Array(String)
    @meta = {} of String => String  # @meta : Hash(String, String)
  end
end

class Person
  # Rule 3: From typed parameters
  def initialize(@name : String, @age : Int32)
    # @name and @age types are known
  end
end

class Config
  # Rule 4: Explicit annotation when unclear
  @data : Hash(String, String | Int32)

  def initialize
    @data = {} of String => String | Int32
  end
end
```

## Union Types

Variables can hold multiple types using union types:

```crystal
# Explicit union type
value : String | Int32 = "hello"
value = 42  # OK, can be Int32 too

# Inferred union type
value = rand < 0.5 ? "hello" : 42  # : String | Int32

# Working with unions
def process(value : String | Int32)
  # Type narrowing with is_a?
  if value.is_a?(String)
    value.upcase  # value is String here
  else
    value * 2     # value is Int32 here
  end
end

# Case with types
def describe(value : String | Int32 | Float64)
  case value
  when String
    "String of length #{value.size}"
  when Int32
    "Integer: #{value}"
  when Float64
    "Float: #{value}"
  end
end
```

## Nilable Types

Nil is tracked by the type system:

```crystal
# Nilable type with ?
name : String? = "Crystal"
name = nil  # OK

# Compile-time nil checking
if name
  # name is String here (not nil)
  puts name.upcase
else
  # name is nil here
  puts "No name"
end

# Safe navigation with try
result = name.try(&.upcase)  # : String?

# Not nil assertion (use sparingly!)
length = name.not_nil!.size  # Raises if nil

# Default values
display_name = name || "Anonymous"  # : String

# Methods returning nilable types
def find_user(id : Int32) : User?
  return nil unless users.has_key?(id)
  users[id]
end
```

## Type Restrictions

Explicit type annotations for clarity and safety:

```crystal
# Method parameters
def add(a : Int32, b : Int32) : Int32
  a + b
end

# Multiple accepted types
def double(x : Int32 | Float64)
  x * 2
end

# Generic type restrictions
def first_element(arr : Array(T)) : T? forall T
  arr.first?
end

# Abstract type restrictions
abstract class Animal
end

class Dog < Animal
end

def feed(animal : Animal)
  # Accepts any Animal subclass
end

# Module type restrictions
module Printable
  abstract def to_s : String
end

def print_item(item : Printable)
  puts item.to_s
end
```

## Type Aliases

Create readable names for complex types:

```crystal
# Simple aliases
alias UserId = Int32
alias Email = String

# Complex type aliases
alias JsonValue = Nil | Bool | Int32 | Int64 | Float32 | Float64 | String | Array(JsonValue) | Hash(String, JsonValue)

# Using aliases
def get_user(id : UserId) : User?
  # ...
end

def parse_json(text : String) : JsonValue
  # ...
end

# Recursive aliases
alias Tree = {value: Int32, children: Array(Tree)}
```

## Generics

Write code that works with multiple types:

```crystal
# Generic class
class Box(T)
  getter value : T

  def initialize(@value : T)
  end

  def replace(new_value : T) : T
    old = @value
    @value = new_value
    old
  end
end

int_box = Box.new(42)        # Box(Int32)
string_box = Box(String).new("hello")  # Explicit type

# Generic methods
def swap(a : T, b : T) : {T, T} forall T
  {b, a}
end

# Multiple type parameters
class Pair(A, B)
  def initialize(@first : A, @second : B)
  end
end

# Constrained generics
def max(a : T, b : T) : T forall T
  a > b ? a : b  # T must support >
end

# Generic modules
module Comparable(T)
  abstract def <=>(other : T) : Int32?

  def <(other : T) : Bool
    (self <=> other).try(&.<(0)) || false
  end

  def >(other : T) : Bool
    (self <=> other).try(&.>(0)) || false
  end
end
```

## Type Casting and Checking

### Type Checking

```crystal
value : String | Int32 = "hello"

# Check type with is_a?
if value.is_a?(String)
  puts value.upcase  # value is String here
end

# Multiple type checks
if value.is_a?(String | Symbol)
  # value is String | Symbol here
end

# Responds to method?
if value.responds_to?(:upcase)
  puts value.upcase
end

# Pattern matching with case
case value
when String
  puts "String: #{value}"
when Int32
  puts "Integer: #{value}"
when Nil
  puts "Value is nil"
else
  puts "Unknown type"
end
```

### Type Casting

```crystal
# Safe casting with as?
value = "42" as String | Int32
int_value = value.as?(Int32)  # : Int32?

if int_value
  puts int_value * 2
end

# Unsafe casting with as (avoid when possible)
string_value = value.as(String)  # Raises if not String

# Type narrowing in conditions
def process(value : String | Int32)
  # After this check, value is String
  return unless value.is_a?(String)

  value.upcase  # Safe to call String methods
end
```

## Typeof and Type Introspection

```crystal
# Get type at compile time
x = 42
type = typeof(x)  # : Int32.class

# Conditional compilation based on type
def handle(x)
  {% if x.type <= Number %}
    x * 2
  {% else %}
    x.to_s
  {% end %}
end

# Get instance type
value = "hello"
value.class  # String at runtime

# Check inheritance
class Animal; end
class Dog < Animal; end

dog = Dog.new
dog.is_a?(Animal)  # true
dog.is_a?(Dog)     # true
Dog < Animal       # true
```

## Modules and Type Composition

```crystal
# Modules add functionality
module Greetable
  abstract def name : String

  def greet
    "Hello, #{name}!"
  end
end

class Person
  include Greetable

  def initialize(@name : String)
  end

  def name : String
    @name
  end
end

# Type restrictions with modules
def welcome(entity : Greetable)
  puts entity.greet
end

# Multiple module inclusion
module Timestamped
  abstract def created_at : Time
  abstract def updated_at : Time
end

class Article
  include Greetable
  include Timestamped

  getter name : String
  getter created_at : Time
  getter updated_at : Time

  def initialize(@name : String)
    @created_at = Time.utc
    @updated_at = Time.utc
  end
end
```

## Advanced Type Features

### Splat Types

```crystal
# Tuple splat
def foo(*args : Int32)
  args  # : Tuple(Int32, ...)
end

# Named tuple splat
def bar(**options : String)
  options  # : NamedTuple(...)
end

# Mixed arguments
def baz(x : Int32, *rest : String, **named : Bool)
  {x, rest, named}
end
```

### Self Type

```crystal
class Chainable
  def tap(&block : self ->)
    yield self
    self
  end

  def then(&block : self -> T) : T forall T
    yield self
  end
end
```

### Abstract Types

```crystal
abstract class Shape
  abstract def area : Float64
  abstract def perimeter : Float64
end

class Circle < Shape
  def initialize(@radius : Float64)
  end

  def area : Float64
    Math::PI * @radius ** 2
  end

  def perimeter : Float64
    2 * Math::PI * @radius
  end
end

# Abstract types in parameters
def total_area(shapes : Array(Shape)) : Float64
  shapes.sum(&.area)
end
```

### Virtual Types

```crystal
class Parent
  def name
    "Parent"
  end
end

class Child < Parent
  def name
    "Child"
  end
end

# Virtual type includes all subclasses
array : Array(Parent) = [Parent.new, Child.new]
array.each do |item|
  puts item.name  # Polymorphic call
end
```

## Type System Best Practices

1. **Let inference work**: Don't add types everywhere
2. **Be explicit at boundaries**: Type method parameters and returns
3. **Use nilable types**: Make nil explicit with `?`
4. **Avoid type casts**: Use type narrowing instead
5. **Create type aliases**: For complex types
6. **Use abstract types**: For polymorphism
7. **Leverage union types**: But keep them simple
8. **Document generic constraints**: Make requirements clear

## Common Type Patterns

### Optional Values

```crystal
def find_by_id(id : Int32) : User?
  users[id]?
end

if user = find_by_id(123)
  puts user.name
else
  puts "User not found"
end
```

### Result Types

```crystal
alias Result(T) = T | Error

class Error
  getter message : String

  def initialize(@message : String)
  end
end

def divide(a : Float64, b : Float64) : Result(Float64)
  return Error.new("Division by zero") if b == 0
  a / b
end

result = divide(10, 2)
case result
when Float64
  puts "Result: #{result}"
when Error
  puts "Error: #{result.message}"
end
```

### Builder Pattern with Types

```crystal
class QueryBuilder
  @conditions = [] of String
  @bindings = [] of String | Int32

  def where(column : String, value : String | Int32) : self
    @conditions << "#{column} = ?"
    @bindings << value
    self
  end

  def build : {String, Array(String | Int32)}
    query = "SELECT * FROM users"
    query += " WHERE #{@conditions.join(" AND ")}" unless @conditions.empty?
    {query, @bindings}
  end
end
```

## Type System Limitations

1. **No runtime type creation**: All types must be known at compile time
2. **Limited reflection**: Can't inspect methods at runtime
3. **No dependent types**: Types can't depend on values
4. **Inheritance limitations**: Single inheritance only (but multiple module inclusion)

Understanding Crystal's type system is essential for writing safe, performant code. The compiler uses this information to:

- Catch errors at compile time
- Generate optimized machine code
- Eliminate runtime type checks
- Enable method inlining

Continue with [Concurrency Model](04-concurrency.md) to learn about Crystal's approach to concurrent programming.
