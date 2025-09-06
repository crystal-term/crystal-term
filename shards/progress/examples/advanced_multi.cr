require "../src/term-progress"

puts "Advanced Multi-Progress Examples\n"

# 1. Parallel Task Processing
puts "1. Parallel Task Processing:"
puts "=" * 30

puts "\nProcessing multiple tasks in parallel...\n"

# Create multi-progress with overall status
multi = Term::Progress::Multi.new("Overall Progress [:bar] :percent")

# Register individual task bars
tasks = [
  {name: "Data Analysis", total: 150, delay: 0.02},
  {name: "Report Generation", total: 80, delay: 0.04},
  {name: "Quality Check", total: 120, delay: 0.025},
  {name: "File Export", total: 200, delay: 0.015}
]

bars = tasks.map do |task|
  multi.register("#{task[:name].ljust(20)} [:bar] :current/:total :percent", task[:total])
end

# Log initial status
multi.log("Starting parallel processing of #{tasks.size} tasks...")

# Start all tasks in parallel
channels = [] of Channel(Nil)

tasks.each_with_index do |task, i|
  channel = Channel(Nil).new
  channels << channel
  
  spawn do
    bar = bars[i]
    
    task[:total].times do |step|
      bar.advance
      
      # Log milestone progress
      if step > 0 && step % (task[:total] // 4) == 0
        progress_percent = ((step.to_f / task[:total]) * 100).round(1)
        multi.log("#{task[:name]} reached #{progress_percent}%")
      end
      
      sleep(task[:delay].seconds)
    end
    
    multi.log("✓ #{task[:name]} completed successfully!")
    channel.send(nil)
  end
end

# Wait for all tasks to complete
channels.each(&.receive)

multi.finish_all("All tasks completed!")
multi.log("Parallel processing finished successfully")

puts "\n" + "=" * 50

# 2. Nested Progress (Build System Simulation)
puts "\n2. Build System Simulation:"
puts "=" * 30

puts "\nSimulating a complex build process...\n"

build_multi = Term::Progress::Multi.new("Build Progress [:bar] :percent")

# Build phases
phases = [
  {name: "Dependencies", steps: ["Download", "Verify", "Install"], items_per_step: [15, 15, 15]},
  {name: "Compilation", steps: ["Parse", "Analyze", "Compile"], items_per_step: [50, 30, 80]},
  {name: "Packaging", steps: ["Bundle", "Compress", "Sign"], items_per_step: [25, 10, 5]}
]

phases.each_with_index do |phase, phase_idx|
  build_multi.log("Starting phase: #{phase[:name]}")
  
  phase[:steps].each_with_index do |step, step_idx|
    step_name = "#{phase[:name]}.#{step}".ljust(20)
    items = phase[:items_per_step][step_idx]
    
    bar = build_multi.register("  #{step_name} [:bar] :current/:total", items)
    
    items.times do |i|
      bar.advance
      
      # Simulate different processing times
      delay = case step
              when "Download"
                0.1.seconds
              when "Compile"
                0.05.seconds
              when "Compress"
                0.15.seconds
              else
                0.03.seconds
              end
      
      sleep(delay)
      
      # Log warnings/errors occasionally
      if rand(100) < 2 # 2% chance
        case rand(3)
        when 0
          build_multi.log("⚠️  Warning: Deprecated API usage in file #{i + 1}")
        when 1
          build_multi.log("ℹ️  Info: Optimizing module #{i + 1}")
        else
          build_multi.log("📦 Package: Including asset #{i + 1}")
        end
      end
    end
    
    # Log completion of each step
    build_multi.log("✓ #{phase[:name]}.#{step} completed")
  end
  
  build_multi.log("Phase '#{phase[:name]}' completed successfully\n")
end

build_multi.finish_all("Build completed successfully!")

puts "\n" + "=" * 50

# 3. Server Deployment Simulation
puts "\n3. Server Deployment:"
puts "=" * 20

puts "\nDeploying to multiple servers...\n"

deployment_multi = Term::Progress::Multi.new("Deployment Status [:bar] :percent")

servers = [
  {name: "web-01", region: "us-east", tasks: 25, speed: 0.08},
  {name: "web-02", region: "us-west", tasks: 25, speed: 0.06},
  {name: "api-01", region: "eu-west", tasks: 30, speed: 0.10},
  {name: "db-01", region: "ap-south", tasks: 40, speed: 0.12}
]

deployment_multi.log("Initiating deployment to #{servers.size} servers...")

# Deploy to servers in parallel
deploy_channels = [] of Channel(Nil)

servers.each do |server|
  channel = Channel(Nil).new
  deploy_channels << channel
  
  spawn do
    server_bar = deployment_multi.register(
      "#{server[:name]} (#{server[:region]}) [:bar] :current/:total :percent", 
      server[:tasks]
    )
    
    deployment_multi.log("🚀 Starting deployment to #{server[:name]}")
    
    server[:tasks].times do |i|
      server_bar.advance
      
      # Simulate deployment steps
      case i
      when 0
        deployment_multi.log("📦 Uploading artifacts to #{server[:name]}")
      when server[:tasks] // 4
        deployment_multi.log("🔄 Restarting services on #{server[:name]}")
      when server[:tasks] // 2
        deployment_multi.log("🔍 Running health checks on #{server[:name]}")
      when (server[:tasks] * 3) // 4
        deployment_multi.log("✅ Health checks passed on #{server[:name]}")
      end
      
      # Simulate network latency based on region
      base_delay = server[:speed]
      network_delay = case server[:region]
                     when "us-east"
                       base_delay * 0.8
                     when "us-west"
                       base_delay * 1.0
                     when "eu-west"
                       base_delay * 1.3
                     else
                       base_delay * 1.8
                     end
      
      sleep(network_delay.seconds)
      
      # Occasional deployment issues
      if rand(50) == 0
        deployment_multi.log("⚠️  Warning: Slow response from #{server[:name]}")
      end
    end
    
    deployment_multi.log("✅ Deployment to #{server[:name]} completed successfully!")
    channel.send(nil)
  end
end

# Wait for all deployments
deploy_channels.each(&.receive)

deployment_multi.finish_all("All deployments completed!")
deployment_multi.log("🎉 Deployment successful across all servers!")

puts "\n" + "=" * 50

# 4. Data Pipeline Processing
puts "\n4. Data Pipeline:"
puts "=" * 18

puts "\nProcessing data through multiple stages...\n"

pipeline_multi = Term::Progress::Multi.new("Data Pipeline [:bar] :percent")

# Pipeline stages
pipeline_stages = [
  {name: "Extract", description: "Reading from data sources", count: 100, delay: 0.05},
  {name: "Transform", description: "Applying business logic", count: 100, delay: 0.08},
  {name: "Validate", description: "Data quality checks", count: 100, delay: 0.03},
  {name: "Load", description: "Writing to destination", count: 100, delay: 0.06}
]

records_processed = 0
total_records = pipeline_stages.sum { |s| s[:count] }

pipeline_multi.log("Starting data pipeline processing #{total_records} records...")

pipeline_stages.each_with_index do |stage, idx|
  pipeline_multi.log("\n--- Stage #{idx + 1}: #{stage[:name]} ---")
  pipeline_multi.log("#{stage[:description]}")
  
  stage_bar = pipeline_multi.register(
    "#{stage[:name].ljust(12)} [:bar] :current/:total records :rate/s",
    stage[:count]
  )
  
  stage[:count].times do |i|
    stage_bar.advance
    records_processed += 1
    
    # Log progress milestones
    if i > 0 && i % (stage[:count] // 5) == 0
      completion = ((i.to_f / stage[:count]) * 100).round(1)
      pipeline_multi.log("#{stage[:name]} stage: #{completion}% complete (#{records_processed}/#{total_records} total records)")
    end
    
    # Simulate data quality issues
    if stage[:name] == "Validate" && rand(20) == 0
      pipeline_multi.log("⚠️  Data quality warning: Record #{i + 1} has missing fields")
    end
    
    # Simulate processing errors
    if rand(100) == 0
      pipeline_multi.log("❌ Error: Failed to process record #{i + 1}, retrying...")
      sleep(stage[:delay].seconds * 2) # Retry takes longer
    end
    
    sleep(stage[:delay].seconds)
  end
  
  pipeline_multi.log("✓ #{stage[:name]} stage completed successfully")
end

pipeline_multi.finish_all("Data pipeline completed!")
pipeline_multi.log("📊 Successfully processed all #{total_records} records through the pipeline")

puts "\n" + "=" * 50

# 5. Monitoring and Logging Example
puts "\n5. System Monitoring:"
puts "=" * 20

puts "\nReal-time system monitoring with alerts...\n"

monitoring_multi = Term::Progress::Multi.new("System Monitor [:bar] :percent")

# Create monitoring bars for different metrics
cpu_bar = monitoring_multi.register("CPU Usage      [:bar] :percent", 100)
memory_bar = monitoring_multi.register("Memory Usage   [:bar] :percent", 100) 
disk_bar = monitoring_multi.register("Disk I/O       [:bar] :percent", 100)
network_bar = monitoring_multi.register("Network Load   [:bar] :percent", 100)

monitoring_multi.log("🖥️  Starting system monitoring...")

# Simulate monitoring for 60 seconds (60 updates at 1 second intervals)
60.times do |second|
  # Simulate realistic system metrics with some fluctuation
  cpu_usage = 20 + rand(40) + 10 * Math.sin(second * 0.1)
  memory_usage = 45 + rand(20) + 5 * Math.sin(second * 0.05)
  disk_usage = 15 + rand(25) + 8 * Math.cos(second * 0.08)
  network_usage = 10 + rand(30) + 15 * Math.sin(second * 0.15)
  
  # Update progress bars
  cpu_bar.update(cpu_usage.to_i64)
  memory_bar.update(memory_usage.to_i64)
  disk_bar.update(disk_usage.to_i64)
  network_bar.update(network_usage.to_i64)
  
  # Alert on high usage
  if cpu_usage > 80
    monitoring_multi.log("🔥 ALERT: High CPU usage detected: #{cpu_usage.round(1)}%")
  elsif cpu_usage > 70
    monitoring_multi.log("⚠️  Warning: Elevated CPU usage: #{cpu_usage.round(1)}%")
  end
  
  if memory_usage > 85
    monitoring_multi.log("💾 ALERT: High memory usage detected: #{memory_usage.round(1)}%")
  end
  
  # Log periodic status updates
  if second > 0 && second % 15 == 0
    monitoring_multi.log("📊 Status update: CPU=#{cpu_usage.round(1)}%, MEM=#{memory_usage.round(1)}%, DISK=#{disk_usage.round(1)}%, NET=#{network_usage.round(1)}%")
  end
  
  sleep(1.seconds)
end

monitoring_multi.finish_all("Monitoring completed")
monitoring_multi.log("📈 System monitoring session ended")

puts "\nAdvanced multi-progress examples complete!"