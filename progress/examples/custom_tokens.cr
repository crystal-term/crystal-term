require "../src/term-progress"

puts "Custom Tokens Examples\n"

# 1. Dynamic token updates
puts "1. Dynamic Token Updates:"
puts "=" * 30

bar = Term::Progress::Bar.new(
  total: 100,
  format: ":task [:bar] :percent (:status)"
)

tasks = ["Initializing", "Loading data", "Processing", "Validating", "Finalizing"]
tasks.each_with_index do |task, i|
  bar.update_tokens(task: task, status: "#{i + 1}/#{tasks.size}")
  
  20.times do
    bar.advance
    sleep(0.03.seconds)
  end
end

bar.update_tokens(status: "Complete")
bar.finish

puts "\n" + "=" * 50

# 2. File processing with custom tokens
puts "\n2. File Processing Example:"
puts "=" * 30

files = ["config.yml", "database.sql", "images.zip", "docs.pdf", "archive.tar.gz"]
total_size = 157_286_400_i64 # ~150MB

bar = Term::Progress::Bar.new(
  total: total_size,
  format: "Processing :filename [:bar] :percent :byte_rate ETA: :eta"
)

files.each do |filename|
  file_size = (total_size / files.size) + (rand(20_000_000) - 10_000_000)
  bar.update_tokens(filename: filename.ljust(15))
  
  chunk_size = file_size // 50
  50.times do
    bar.advance(chunk_size.to_i64)
    sleep(0.02.seconds)
  end
end

bar.finish("All files processed!")

puts "\n" + "=" * 50

# 3. Network operations with detailed status
puts "\n3. Network Operations:"
puts "=" * 25

endpoints = [
  "https://api.example.com/users",
  "https://api.example.com/posts", 
  "https://api.example.com/comments",
  "https://api.example.com/analytics"
]

bar = Term::Progress::Bar.new(
  total: endpoints.size * 100,
  format: ":operation [:bar] :percent | :endpoint | :speed req/s"
)

operations = ["GET", "POST", "PUT", "DELETE"]

endpoints.each_with_index do |endpoint, i|
  operation = operations[i % operations.size]
  short_endpoint = endpoint.split("/").last.capitalize.ljust(10)
  
  bar.update_tokens(
    operation: operation,
    endpoint: short_endpoint,
    speed: "#{rand(50) + 10}"
  )
  
  100.times do
    bar.advance
    sleep(0.015.seconds)
  end
end

bar.finish("API testing complete!")

puts "\n" + "=" * 50

# 4. Build/compile process simulation
puts "\n4. Build Process Simulation:"
puts "=" * 30

build_steps = [
  {phase: "Parsing", detail: "source files"},
  {phase: "Analyzing", detail: "dependencies"},
  {phase: "Compiling", detail: "modules"},
  {phase: "Linking", detail: "libraries"},
  {phase: "Optimizing", detail: "bytecode"}
]

bar = Term::Progress::Bar.new(
  total: build_steps.size * 25,
  format: ":phase :detail [:bar] :current/:total files (:percent)"
)

build_steps.each do |step|
  bar.update_tokens(
    phase: step[:phase].ljust(12),
    detail: step[:detail].ljust(12)
  )
  
  25.times do
    bar.advance
    sleep(0.04.seconds)
  end
end

bar.finish("Build successful!")

puts "\n" + "=" * 50

# 5. Custom formatting with calculations
puts "\n5. Custom Calculations:"
puts "=" * 25

bar = Term::Progress::Bar.new(
  total: 200,
  format: ":job [:bar] :percent | Mem: :memory | CPU: :cpu%"
)

200.times do |i|
  # Simulate memory and CPU usage
  memory_mb = 128 + (i * 2) + rand(20)
  cpu_percent = 20 + (i * 0.3).to_i + rand(10)
  
  bar.update_tokens(
    job: "Task #{(i / 20) + 1}".ljust(8),
    memory: "#{memory_mb}MB".ljust(8),
    cpu: cpu_percent.to_s.ljust(2)
  )
  
  bar.advance
  sleep(0.02.seconds)
end

bar.finish("Processing complete!")

puts "\n" + "=" * 50

# 6. Multi-line information display
puts "\n6. Rich Information Display:"
puts "=" * 30

bar = Term::Progress::Bar.new(
  total: 150,
  format: ":title [:bar] :percent\n         Time: :elapsed | Remaining: :eta | Speed: :rate/s"
)

datasets = ["Training data", "Validation set", "Test samples"]
datasets.each_with_index do |dataset, i|
  bar.update_tokens(title: dataset.ljust(15))
  
  50.times do
    bar.advance
    sleep(0.03.seconds)
  end
  
  # Add a log message between datasets
  if i < datasets.size - 1
    bar.log("✓ #{dataset} processed successfully")
  end
end

bar.finish("All datasets processed!")

puts "\nCustom tokens examples complete!"