# Macros and Metaprogramming in Crystal

Crystal's macro system provides powerful compile-time code generation capabilities. Unlike Ruby's runtime metaprogramming, Crystal macros run at compile time, maintaining type safety and performance.

## Macro Basics

### Simple Macros

```crystal
# Basic macro definition
macro say_hello
  puts "Hello from macro!"
end

say_hello  # Expands at compile time

# Macro with arguments
macro define_method(name, content)
  def {{name}}
    {{content}}
  end
end

define_method foo, "bar"
puts foo  # => "bar"

# Macro with block
macro benchmark(name, &block)
  start = Time.monotonic
  {{yield}}
  elapsed = Time.monotonic - start
  puts "{{name}} took #{elapsed.total_milliseconds}ms"
end

benchmark "calculation" do
  sum = 0
  1000.times { |i| sum += i }
end
```

### Macro Syntax

```crystal
# Interpolation with {{ }}
macro create_getter(name, type)
  def {{name}} : {{type}}
    @{{name}}
  end
end

class Person
  @name : String
  
  def initialize(@name : String)
  end
  
  create_getter name, String
end

# Embedding code with {% %}
macro debug_info(var)
  {% if flag?(:debug) %}
    puts "Debug: {{var}} = #{{{var}}}"
  {% end %}
end

# Compile with: crystal build -Ddebug app.cr
debug_info(my_variable)
```

## Macro Language Features

### Control Flow in Macros

```crystal
# If statements
macro define_comparison(type)
  {% if type.resolve < Number %}
    def >(other : {{type}})
      value > other.value
    end
  {% elsif type.resolve < String %}
    def >(other : {{type}})
      value.compare(other.value) > 0
    end
  {% else %}
    {% raise "Unsupported type for comparison" %}
  {% end %}
end

# For loops
macro create_tuple_accessors(*names)
  {% for name, index in names %}
    def {{name.id}}
      @tuple[{{index}}]
    end
  {% end %}
end

class Point3D
  def initialize(@tuple : {Float64, Float64, Float64})
  end
  
  create_tuple_accessors x, y, z
end
```

### Macro Variables and Methods

```crystal
macro analyze_type(type)
  {% type_info = type.resolve %}
  
  # Type information
  puts "Type name: {{type_info.name}}"
  puts "Type ID: {{type_info.id}}"
  puts "Is class?: {{type_info.class?}}"
  puts "Is struct?: {{type_info.struct?}}"
  
  # Methods
  puts "Instance methods:"
  {% for method in type_info.methods %}
    puts "  - {{method.name}}"
  {% end %}
  
  # Instance variables
  puts "Instance variables:"
  {% for ivar in type_info.instance_vars %}
    puts "  - @{{ivar.name}} : {{ivar.type}}"
  {% end %}
end

class Example
  @value : Int32 = 0
  
  def foo; end
  def bar; end
end

analyze_type(Example)
```

## Advanced Macro Techniques

### Method Generation

```crystal
# Generate methods for multiple types
macro define_converter(from_type, to_type)
  def to_{{to_type.id.downcase}} : {{to_type}}
    {{to_type}}.new(self)
  end
end

class Temperature
  def initialize(@celsius : Float64)
  end
  
  define_converter self, Fahrenheit
  define_converter self, Kelvin
end

# Generate property methods
macro json_property(name, type, key = nil)
  {% key = key || name.id.stringify %}
  
  @[JSON::Field(key: {{key}})]
  property {{name}} : {{type}}
end

class User
  include JSON::Serializable
  
  json_property name, String
  json_property email, String
  json_property age, Int32, key: "user_age"
end
```

### DSL Creation

```crystal
# Create a DSL for building HTML
macro tag(name, content = nil, **attributes, &block)
  %tag = String.build do |io|
    io << "<{{name.id}}"
    
    {% for key, value in attributes %}
      io << " {{key.id}}=\"{{value}}\""
    {% end %}
    
    io << ">"
    
    {% if content %}
      io << {{content}}
    {% elsif block %}
      io << {{yield}}
    {% end %}
    
    io << "</{{name.id}}>"
  end
  
  %tag
end

# Usage
html = tag :div, class: "container" do
  tag :h1, "Welcome"
  tag :p, "This is a paragraph", class: "text"
end

# State machine DSL
macro state_machine(&block)
  {% states = [] of StringLiteral %}
  {% transitions = [] of HashLiteral %}
  
  macro state(name)
    \{% states << name.id.stringify %}
  end
  
  macro transition(from, to, event)
    \{% transitions << {from: from, to: to, event: event} %}
  end
  
  {{yield}}
  
  # Generate state enum
  enum State
    {% for state in states %}
      {{state.id.capitalize}}
    {% end %}
  end
  
  # Generate transition methods
  {% for transition in transitions %}
    def {{transition[:event].id}}
      if @state == State::{{transition[:from].id.capitalize}}
        @state = State::{{transition[:to].id.capitalize}}
      else
        raise "Invalid transition"
      end
    end
  {% end %}
end

class Door
  @state = State::Closed
  
  state_machine do
    state :open
    state :closed
    
    transition :closed, :open, :open_door
    transition :open, :closed, :close_door
  end
end
```

### Hook Methods

```crystal
# Method added hook
macro method_added(method)
  {% if method.name.starts_with?("test_") %}
    TESTS << ->{ {{method.name}} }
  {% end %}
end

# Inherited hook
macro inherited
  {% puts "Class #{@type} inherits from #{@type.superclass}" %}
  
  # Register subclass
  SUBCLASSES << {{@type}}
end

# Included hook
module Trackable
  macro included
    @@instances = [] of {{@type}}
    
    def initialize
      @@instances << self
      previous_def
    end
    
    def self.instances
      @@instances
    end
  end
end

class Model
  include Trackable
end
```

### Fresh Variables

```crystal
# Generate unique variable names
macro safe_assignment(value)
  %var{__LINE__} = {{value}}
  puts %var{__LINE__}
end

safe_assignment(10)
safe_assignment(20)  # Different variable

# In loops
macro multi_assign(*values)
  {% for value, index in values %}
    %var{index} = {{value}}
  {% end %}
  
  {% for value, index in values %}
    puts %var{index}
  {% end %}
end
```

## Compile-Time Computation

```crystal
# Fibonacci at compile time
macro fib(n)
  {% if n <= 1 %}
    {{n}}
  {% else %}
    {{fib(n - 1) + fib(n - 2)}}
  {% end %}
end

FIB_SEQUENCE = {
  {% for i in 0..10 %}
    {{fib(i)}},
  {% end %}
}

# Generate lookup tables
macro generate_sin_table(size)
  {
    {% for i in 0...size %}
      {{Math.sin(2 * Math::PI * i / size)}},
    {% end %}
  }
end

SIN_TABLE = generate_sin_table(360)

# Type-safe enum operations
macro enum_with_features(name, &block)
  enum {{name}}
    {{yield}}
  end
  
  class {{name}}
    # Generate from_string method
    def self.from_string(str : String) : {{name}}?
      case str.downcase
      {% for member in @type.constants %}
      when {{member.stringify.downcase}}
        {{member}}
      {% end %}
      else
        nil
      end
    end
    
    # Generate to_string method
    def to_string : String
      case self
      {% for member in @type.constants %}
      when {{member}}
        {{member.stringify}}
      {% end %}
      else
        raise "Unknown enum value"
      end
    end
  end
end

enum_with_features Color do
  Red
  Green
  Blue
end

color = Color.from_string("red")  # => Color::Red
```

## Real-World Macro Examples

### ORM-like Functionality

```crystal
macro model(name, &block)
  class {{name}}
    {% properties = [] of TypeDeclaration %}
    
    macro property(decl)
      \{% properties << decl %}
      property \{{decl}}
    end
    
    {{yield}}
    
    # Generate from_hash method
    def self.from_hash(hash : Hash(String, JSON::Any))
      instance = {{name}}.new
      {% for prop in properties %}
        if value = hash[{{prop.var.stringify}}]?
          instance.{{prop.var}} = value.as({{prop.type}})
        end
      {% end %}
      instance
    end
    
    # Generate to_hash method
    def to_hash
      {
        {% for prop in properties %}
          {{prop.var.stringify}} => {{prop.var}},
        {% end %}
      }
    end
  end
end

model User do
  property name : String = ""
  property email : String = ""
  property age : Int32 = 0
end
```

### Method Delegation

```crystal
macro delegate(*methods, to object)
  {% for method in methods %}
    def {{method.id}}(*args, **options)
      {{object.id}}.{{method.id}}(*args, **options)
    end
  {% end %}
end

class OrderService
  def initialize(@repository : OrderRepository)
  end
  
  delegate find, find_by_id, all, to: @repository
  
  def process(id : Int32)
    order = find_by_id(id)  # Delegates to @repository
    # Process order
  end
end
```

### Memoization

```crystal
macro memoize(method)
  @__memoized_{{method.name}} : {{method.return_type}}?
  
  def {{method.name}}({{method.args.splat}}){% if method.return_type %} : {{method.return_type}}{% end %}
    @__memoized_{{method.name}} ||= begin
      {{method.body}}
    end
  end
end

class Calculator
  memoize def expensive_computation : Int32
    puts "Computing..."
    sleep 1
    42
  end
end
```

### Serialization

```crystal
macro serializable(*properties)
  # Include necessary modules
  include JSON::Serializable
  include YAML::Serializable
  
  # Define properties
  {% for prop in properties %}
    {% if prop.is_a?(TypeDeclaration) %}
      property {{prop}}
    {% else %}
      property {{prop.id}} : String
    {% end %}
  {% end %}
  
  # Generate constructor
  def initialize(
    {% for prop in properties %}
      {% if prop.is_a?(TypeDeclaration) %}
        @{{prop.var}} : {{prop.type}},
      {% else %}
        @{{prop.id}} : String,
      {% end %}
    {% end %}
  )
  end
end

class Config
  serializable(
    host : String,
    port : Int32,
    ssl : Bool = false
  )
end
```

## Debugging Macros

```crystal
# Print macro expansion
macro debug_macro(code)
  {% puts "Macro expansion:" %}
  {% puts code.stringify %}
  {{code}}
end

debug_macro(1 + 2 + 3)

# Inspect types
macro inspect_type(expr)
  {% puts "Expression: #{expr}" %}
  {% puts "Type: #{expr.class_name}" %}
  {% if expr.is_a?(Call) %}
    {% puts "Method: #{expr.name}" %}
    {% puts "Receiver: #{expr.receiver}" %}
    {% puts "Args: #{expr.args}" %}
  {% end %}
end

# Use p() in macros
macro debug_value(expr)
  {% p expr %}
  {% p expr.class_name %}
  {% p expr.id %}
end
```

## Macro Best Practices

### 1. Keep Macros Simple

```crystal
# Bad - complex logic in macro
macro complex_macro(x)
  {% if x > 10 && x < 20 || x == 5 %}
    # Complex logic
  {% end %}
end

# Good - delegate to methods
macro simple_macro(x)
  handle_value({{x}})
end

def handle_value(x)
  # Complex logic in regular method
end
```

### 2. Use Clear Names

```crystal
# Bad
macro m(n, t)
  property {{n}} : {{t}}
end

# Good
macro json_field(name, type)
  @[JSON::Field]
  property {{name}} : {{type}}
end
```

### 3. Document Macro Behavior

```crystal
# Generates getter and setter methods for a property
# with optional validation.
#
# Example:
#   validated_property age : Int32 do |value|
#     raise "Age must be positive" if value < 0
#   end
macro validated_property(decl, &block)
  # Implementation
end
```

### 4. Avoid Side Effects

```crystal
# Bad - modifies global state
macro register_class
  {% CLASSES << @type %}
end

# Good - explicit registration
macro register_class(registry)
  {{registry}}.register({{@type}})
end
```

## Common Pitfalls

1. **Forgetting stringify**: Use `.stringify` to convert AST nodes to strings
2. **Scope issues**: Macros have different scope rules than methods
3. **Type resolution**: Use `.resolve` to get actual type information
4. **Syntax restrictions**: Not all Crystal syntax works in macro land
5. **Debugging difficulty**: Macro errors can be cryptic

## Macro vs Method

Use macros when you need:
- Compile-time code generation
- Type introspection
- DSL creation
- Performance-critical inlining
- Conditional compilation

Use methods when:
- Runtime behavior is needed
- Logic is complex
- Debugging is important
- Code reuse across projects

Crystal's macro system is powerful but should be used judiciously. Well-designed macros can eliminate boilerplate and create expressive APIs while maintaining type safety and performance.

Next: [Testing with Spectator](08-testing.md)