require "../src/term-progress"

puts "Progress Bar Formatters Showcase\n"

# 1. Built-in formatters
puts "1. Built-in Format Styles:"
puts "=" * 40

formats = {
  "default"  => Term::Progress::Formatters::FORMATS["default"],
  "minimal"  => Term::Progress::Formatters::FORMATS["minimal"], 
  "download" => Term::Progress::Formatters::FORMATS["download"],
  "tasks"    => Term::Progress::Formatters::FORMATS["tasks"],
  "classic"  => Term::Progress::Formatters::FORMATS["classic"],
  "detailed" => Term::Progress::Formatters::FORMATS["detailed"]
}

formats.each do |name, format_string|
  puts "\n#{name.capitalize} format:"
  puts "Template: #{format_string}"
  
  bar = Term::Progress::Bar.new(total: 100, format: format_string)
  bar.update_tokens(title: "Sample Task")
  
  # Simulate progress
  25.times do |i|
    bar.advance(4)
    sleep(0.02.seconds)
  end
  bar.finish("Complete!")
end

puts "\n" + "=" * 50

# 2. Custom character sets
puts "\n2. Custom Character Sets:"
puts "=" * 30

character_sets = [
  {name: "Classic ASCII", complete: "#", incomplete: "-", head: ">"},
  {name: "Blocks", complete: "█", incomplete: "░", head: nil},
  {name: "Arrows", complete: "→", incomplete: "·", head: "➤"},
  {name: "Dots", complete: "●", incomplete: "○", head: "◐"},
  {name: "Pipes", complete: "|", incomplete: " ", head: nil}
]

character_sets.each do |set|
  puts "\n#{set[:name]}:"
  
  bar = Term::Progress::Bar.new(
    total: 50,
    format: "Progress: [:bar] :percent",
    complete_char: set[:complete],
    incomplete_char: set[:incomplete],
    head_char: set[:head]
  )
  
  50.times do |i|
    bar.advance
    sleep(0.015.seconds)
  end
  bar.finish
end

puts "\n" + "=" * 50

# 3. Width variations
puts "\n3. Different Bar Widths:"
puts "=" * 25

widths = [10, 20, 40, 60]
widths.each do |width|
  puts "\nWidth #{width}:"
  
  bar = Term::Progress::Bar.new(
    total: 40,
    width: width,
    format: "[:bar] :percent"
  )
  
  40.times do |i|
    bar.advance
    sleep(0.01.seconds)
  end
  bar.finish
end

puts "\n" + "=" * 50

# 4. Block-style smooth progress
puts "\n4. Smooth Block Progress:"
puts "=" * 25

puts "\nSmooth rendering with fractional blocks:"
bar = Term::Progress::Bar.new(
  total: 127,
  format: "Loading [:blocks] :percent"
)

127.times do |i|
  bar.advance
  sleep(0.02.seconds)
end
bar.finish("Ready!")

puts "\n" + "=" * 50

# 5. Dots-style progress
puts "\n5. Dots-style Progress:"
puts "=" * 20

puts "\nDots visualization:"
bar = Term::Progress::Bar.new(
  total: 80,
  format: "Processing [:dots] :current/:total"
)

80.times do |i|
  bar.advance
  sleep(0.025.seconds)
end
bar.finish("Done!")

puts "\n\nFormatters showcase complete!"