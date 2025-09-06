require "../src/term-progress"

puts "Rate Calculation and Timing Examples\n"

# 1. Data Transfer Rate Demonstration
puts "1. Data Transfer Rates:"
puts "=" * 25

puts "\nSimulating different transfer speeds...\n"

transfer_scenarios = [
  {name: "Slow Connection", speed_kbps: 128, size_mb: 5},
  {name: "Broadband", speed_kbps: 1000, size_mb: 25},
  {name: "High-Speed", speed_kbps: 5000, size_mb: 100}
]

transfer_scenarios.each do |scenario|
  puts "#{scenario[:name]} (#{scenario[:speed_kbps]} kbps):"
  
  total_bytes = scenario[:size_mb] * 1024 * 1024
  speed_bps = scenario[:speed_kbps] * 1024 # Convert to bytes per second
  
  bar = Term::Progress::Bar.new(
    total: total_bytes.to_i64,
    format: "  [:bar] :percent :byte_rate | ETA: :eta | :elapsed elapsed"
  )
  
  transferred = 0
  while transferred < total_bytes
    # Simulate transfer with realistic speed variation
    chunk_size = Math.min(speed_bps / 20, total_bytes - transferred) # 50ms chunks
    transferred += chunk_size
    
    bar.update(transferred.to_i64)
    sleep(0.005.seconds) # 5ms delay = 200 updates per second
  end
  
  bar.finish("Transfer complete!")
  puts "  Final rate: #{bar.meter.format_rate(bar.meter.mean_rate)}"
  puts "  Total time: #{bar.meter.format_time(bar.meter.elapsed_time.total_seconds)}"
  puts
end

puts "=" * 50

# 2. Processing Rate Comparisons
puts "\n2. Processing Rate Comparisons:"
puts "=" * 35

processing_tasks = [
  {name: "Text Processing", items_per_second: 1000, total_items: 50000},
  {name: "Image Resizing", items_per_second: 50, total_items: 2000},
  {name: "Video Encoding", items_per_second: 2, total_items: 60},
  {name: "Data Validation", items_per_second: 500, total_items: 25000}
]

processing_tasks.each do |task|
  puts "\n#{task[:name]}:"
  
  bar = Term::Progress::Bar.new(
    total: task[:total_items].to_i64,
    format: "  [:bar] :current/:total items :percent | :rate/s | Mean: :mean_rate/s"
  )
  
  processed = 0
  target_rate = task[:items_per_second]
  
  while processed < task[:total_items]
    # Simulate realistic processing with rate variation
    variation = Math.max(1, target_rate // 4)
    actual_rate = target_rate + rand(variation) - (variation // 2)
    items_this_update = Math.min(Math.max(1, actual_rate // 10), task[:total_items] - processed)
    processed += items_this_update
    
    bar.update(processed.to_i64)
    sleep(0.01.seconds) # 100 updates per second
  end
  
  bar.finish("Processing complete!")
  
  # Show final statistics
  final_rate = bar.meter.mean_rate
  efficiency = (final_rate / target_rate * 100).round(1)
  puts "  Target rate: #{target_rate}/s | Actual rate: #{final_rate.round(1)}/s | Efficiency: #{efficiency}%"
end

puts "\n" + "=" * 50

# 3. ETA Accuracy Demonstration
puts "\n3. ETA Accuracy Over Time:"
puts "=" * 30

puts "\nDemonstrating ETA convergence..."

# Simulate a task with variable processing speed
bar = Term::Progress::Bar.new(
  total: 100_i64,
  format: "Variable Speed Task [:bar] :percent | ETA: :eta | Elapsed: :elapsed"
)

# Track ETA predictions for analysis
eta_predictions = [] of Float64?

100.times do |i|
  # Simulate speed that changes over time (starts slow, gets faster)
  progress_factor = i / 100.0
  base_delay = 0.005 # 5ms base
  speed_factor = 1.0 + progress_factor # Gets up to 2x faster
  delay = base_delay / speed_factor
  
  bar.advance
  
  # Record ETA every 20 iterations
  if i % 20 == 0
    eta = bar.meter.eta(bar.current, bar.total)
    eta_predictions << eta
    
    if eta
      puts "  Step #{i}: ETA = #{bar.meter.format_time(eta)} | Rate = #{bar.meter.rate.round(1)}/s"
    else
      puts "  Step #{i}: ETA = calculating... | Rate = #{bar.meter.rate.round(1)}/s"
    end
  end
  
  sleep(delay.seconds)
end

bar.finish("Task completed!")

puts "\n" + "=" * 50

# 4. Byte Rate Formatting Examples
puts "\n4. Byte Rate Formatting:"
puts "=" * 25

puts "\nDifferent data size examples:\n"

data_scenarios = [
  {name: "Small files", bytes_per_sec: 15_360},      # ~15 KB/s
  {name: "Medium files", bytes_per_sec: 2_097_152},  # ~2 MB/s
  {name: "Large files", bytes_per_sec: 52_428_800},  # ~50 MB/s
  {name: "Huge files", bytes_per_sec: 1_073_741_824} # ~1 GB/s
]

data_scenarios.each do |scenario|
  puts "#{scenario[:name]}:"
  
  # Create a meter to demonstrate formatting
  meter = Term::Progress::Meter.new
  
  # Simulate some data transfer to establish rate
  transferred = 0_i64
  10.times do |i|
    transferred += scenario[:bytes_per_sec].to_i64
    meter.update(transferred)
    sleep(0.01.seconds)
  end
  
  puts "  Raw bytes/sec: #{scenario[:bytes_per_sec]}"
  puts "  Formatted rate: #{meter.format_rate(scenario[:bytes_per_sec].to_f)}"
  puts "  Mean rate: #{meter.format_rate(meter.mean_rate)}"
  puts
end

puts "=" * 50

# 5. Time Formatting Examples
puts "\n5. Time Formatting Examples:"
puts "=" * 30

time_examples = [
  {seconds: 30.0, description: "Half minute"},
  {seconds: 125.0, description: "Just over 2 minutes"},
  {seconds: 3661.0, description: "About an hour"},
  {seconds: 7323.0, description: "Over 2 hours"},
  {seconds: Float64::INFINITY, description: "Infinite time"},
  {seconds: 0.0, description: "No time"},
  {seconds: -10.0, description: "Invalid negative time"}
]

meter = Term::Progress::Meter.new

puts "\nTime formatting examples:"
time_examples.each do |example|
  formatted = meter.format_time(example[:seconds])
  puts "  #{example[:description].ljust(25)}: #{example[:seconds].inspect.ljust(15)} → #{formatted}"
end

puts "\n" + "=" * 50

# 6. Performance Monitoring
puts "\n6. Performance Monitoring:"
puts "=" * 25

puts "\nMonitoring system performance over time...\n"

# Simulate a system monitoring scenario
bar = Term::Progress::Bar.new(
  total: 60_i64, # 1 minute at faster intervals
  format: "Monitoring [:bar] :percent | Samples: :rate/s | Avg: :mean_rate/s | Time: :elapsed"
)

sample_rates = [] of Float64

60.times do |i|
  # Simulate varying system load
  load_factor = 1.0 + 0.3 * Math.sin(i * 0.1) # Sinusoidal load variation
  processing_time = 0.01 + (rand(0.01) * load_factor) # Much faster
  
  bar.advance
  sample_rates << bar.meter.rate
  
  # Show performance stats every 15 iterations
  if i > 0 && i % 15 == 0
    current_avg = sample_rates.sum / sample_rates.size
    recent_avg = sample_rates.last(15).sum / 15.0
    
    bar.log("Performance update: Overall avg=#{current_avg.round(2)}/s, Recent avg=#{recent_avg.round(2)}/s")
  end
  
  sleep(processing_time.seconds)
end

bar.finish("Monitoring complete!")

final_avg_rate = sample_rates.sum / sample_rates.size
puts "Final average rate: #{final_avg_rate.round(3)} samples/second"

puts "\nRates and timing examples complete!"