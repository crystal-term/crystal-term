require "../src/term-progress"

puts "Real-World Progress Bar Examples\n"

# 1. File Download Simulator
puts "1. File Download Simulation:"
puts "=" * 30

def simulate_download(filename : String, size_mb : Int32)
  puts "\nDownloading #{filename} (#{size_mb}MB)..."
  
  total_bytes = size_mb * 1024 * 1024
  bar = Term::Progress::Bar.new(
    total: total_bytes.to_i64,
    format: "#{filename} [:bar] :percent :byte_rate ETA: :eta"
  )
  
  chunk_size = 64 * 1024 # 64KB chunks
  downloaded = 0
  
  while downloaded < total_bytes
    # Simulate variable download speeds
    current_chunk = Math.min(chunk_size + rand(32768), total_bytes - downloaded)
    downloaded += current_chunk
    
    bar.update(downloaded.to_i64)
    sleep((0.001 + rand(0.002)).seconds) # Variable network delay
  end
  
  bar.finish("Download complete!")
end

# Download several files
downloads = [
  {name: "update.zip", size: 15},
  {name: "dataset.csv", size: 45},
  {name: "backup.tar.gz", size: 128}
]

downloads.each do |download|
  simulate_download(download[:name], download[:size])
  sleep(0.1.seconds)
end

puts "\n" + "=" * 50

# 2. Database Operations
puts "\n2. Database Migration:"
puts "=" * 25

tables = ["users", "posts", "comments", "categories", "tags", "sessions"]
records_per_table = [10000, 25000, 50000, 1500, 800, 30000]

puts "\nMigrating database schema..."

tables.each_with_index do |table, i|
  records = records_per_table[i]
  puts "\nProcessing table: #{table}"
  
  bar = Term::Progress::Bar.new(
    total: records.to_i64,
    format: "  #{table.ljust(12)} [:bar] :current/:total records (:percent) :rate/s"
  )
  
  batch_size = [100, 500, 1000].sample
  processed = 0
  
  while processed < records
    current_batch = Math.min(batch_size, records - processed)
    processed += current_batch
    
    bar.update(processed.to_i64)
    sleep((0.001 + rand(0.001)).seconds) # Database operation time
  end
  
  bar.finish("✓ Complete")
end

puts "\nDatabase migration completed successfully!"

puts "\n" + "=" * 50

# 3. Image Processing Pipeline
puts "\n3. Image Processing Pipeline:"
puts "=" * 35

image_operations = [
  {name: "Loading images", count: 150},
  {name: "Resizing", count: 150}, 
  {name: "Applying filters", count: 150},
  {name: "Generating thumbnails", count: 150},
  {name: "Optimizing", count: 150},
  {name: "Saving results", count: 150}
]

puts "\nProcessing image batch..."

image_operations.each do |operation|
  puts "\n#{operation[:name]}..."
  
  bar = Term::Progress::Bar.new(
    total: operation[:count].to_i64,
    format: "  [:bar] :current/:total images :percent | :rate img/s | :elapsed"
  )
  
  operation[:count].times do |i|
    # Simulate different processing times for different operations
    processing_time = case operation[:name]
                     when "Loading images"
                       0.001.seconds
                     when "Resizing"
                       0.003.seconds  
                     when "Applying filters"
                       0.005.seconds
                     when "Generating thumbnails"
                       0.002.seconds
                     when "Optimizing"
                       0.004.seconds
                     else
                       0.0015.seconds
                     end
    
    bar.advance
    sleep(processing_time + rand(0.001).seconds)
  end
  
  bar.finish("✓ Complete")
end

puts "\nImage processing pipeline completed!"

puts "\n" + "=" * 50

# 4. Code Analysis/Linting
puts "\n4. Code Analysis:"
puts "=" * 20

source_files = [
  "src/main.cr", "src/config.cr", "src/database.cr", "src/models/user.cr",
  "src/models/post.cr", "src/controllers/api.cr", "src/views/layout.cr",
  "src/utils/helpers.cr", "spec/main_spec.cr", "spec/models_spec.cr"
]

analysis_types = ["Syntax check", "Style check", "Security scan", "Performance analysis"]

puts "\nRunning code analysis..."

analysis_types.each do |analysis|
  puts "\n#{analysis}:"
  
  bar = Term::Progress::Bar.new(
    total: source_files.size.to_i64,
    format: "  [:bar] :current/:total files :percent | :filename"
  )
  
  source_files.each do |file|
    bar.update_tokens(filename: file.ljust(25))
    bar.advance
    
    # Simulate analysis time based on file type
    analysis_time = if file.includes?("spec")
                     0.002.seconds
                   elsif file.includes?("models")
                     0.004.seconds
                   else
                     0.003.seconds
                   end
    
    sleep(analysis_time + rand(0.001).seconds)
  end
  
  bar.finish("✓ Complete")
end

puts "\nCode analysis finished!"

puts "\n" + "=" * 50

# 5. System Backup
puts "\n5. System Backup:"
puts "=" * 18

backup_paths = [
  {path: "/home/user/documents", size_gb: 0.5},
  {path: "/home/user/pictures", size_gb: 1.8},
  {path: "/home/user/videos", size_gb: 2.2},
  {path: "/etc/config", size_gb: 0.1},
  {path: "/var/log", size_gb: 0.4}
]

puts "\nStarting system backup..."

total_size = backup_paths.sum { |p| p[:size_gb] }
puts "Total backup size: #{total_size.round(1)}GB\n"

overall_progress = 0.0

backup_paths.each do |backup|
  path = backup[:path]
  size_gb = backup[:size_gb]
  
  puts "\nBacking up: #{path}"
  
  # Convert GB to bytes for progress tracking
  total_bytes = (size_gb * 1024 * 1024 * 1024).to_i64
  
  bar = Term::Progress::Bar.new(
    total: total_bytes,
    format: "  [:bar] :percent :byte_rate | :elapsed/:eta"
  )
  
  # Simulate backup with chunks
  chunk_size = 50 * 1024 * 1024 # 50MB chunks (faster)
  backed_up = 0_i64
  
  while backed_up < total_bytes
    current_chunk = Math.min(chunk_size, total_bytes - backed_up)
    backed_up += current_chunk
    
    bar.update(backed_up)
    sleep((0.0005 + rand(0.001)).seconds) # Faster I/O time
  end
  
  bar.finish("✓ Complete")
  overall_progress += size_gb
  
  puts "  Progress: #{(overall_progress / total_size * 100).round(1)}% of total backup"
end

puts "\nSystem backup completed successfully!"
puts "Total data backed up: #{total_size.round(1)}GB"

puts "\nReal-world examples complete!"