require "../src/term-progress"

puts "Basic Progress Bar Example\n"

# Simple progress bar
puts "1. Basic progress bar:"
bar = Term::Progress::Bar.new(total: 100)

100.times do |i|
  bar.advance
  sleep(0.02.seconds)
end
bar.finish("Complete!")

puts "\n2. Download simulation:"
download_bar = Term::Progress::Bar.new(
  total: 1024,
  format: "Downloading [:bar] :percent :byte_rate ETA: :eta"
)

1024.times do |i|
  download_bar.advance
  sleep(0.005.seconds)
end
download_bar.finish("Downloaded!")

puts "\n3. Custom format with title:"
custom_bar = Term::Progress::Bar.new(
  total: 50,
  format: ":title [:bar] :current/:total (:percent)"
)
custom_bar.update_tokens(title: "Processing files")

50.times do |i|
  custom_bar.advance
  sleep(0.03.seconds)
end
custom_bar.finish("Done!")

puts "\n4. Block-style progress (smooth Unicode blocks):"
block_bar = Term::Progress::Bar.new(
  total: 75,
  format: "Loading :blocks :percent"
)

75.times do |i|
  block_bar.advance
  sleep(0.05.seconds)  # Slower to see the smooth block transitions
end
block_bar.finish

puts "\nAll examples completed!"