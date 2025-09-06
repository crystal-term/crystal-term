require "../src/term-progress"

puts "Multiple Progress Bars Example\n"

# Create multi-progress manager
multi = Term::Progress::Multi.new("Overall Progress [:bar] :percent")

# Register multiple progress bars
download_bar = multi.register("Download [:bar] :byte_rate", total: 500)
install_bar = multi.register("Install  [:bar] :percent", total: 100) 
config_bar = multi.register("Config   [:bar] :current/:total", total: 25)

# Simulate concurrent operations
spawn do
  500.times do
    download_bar.advance
    sleep(0.005.seconds)
  end
end

spawn do
  100.times do
    install_bar.advance
    sleep(0.015.seconds)
  end
end

spawn do
  25.times do
    config_bar.advance
    sleep(0.05.seconds)
  end
end

# Wait for all to complete
until multi.done?
  sleep(0.01.seconds)
end

multi.finish_all("All tasks completed!")

puts "\nMulti-progress example completed!"