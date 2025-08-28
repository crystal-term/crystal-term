module ProgressFixtures
  # Common test configurations
  BASIC_CONFIG = {
    total: 100_i64,
    format: "[:bar] :percent :current/:total"
  }
  
  DOWNLOAD_CONFIG = {
    total: 1024_i64,
    format: "Downloading [:bar] :percent :byte_rate ETA: :eta"
  }
  
  CUSTOM_CONFIG = {
    total: 50_i64,
    format: ":title [:bar] :current/:total (:percent)",
    complete_char: "#",
    incomplete_char: "-",
    head_char: ">"
  }
  
  # Format string examples
  ALL_FORMATS = {
    "default" => "[:bar] :percent :current/:total",
    "minimal" => ":percent :bar",
    "download" => "[:bar] :percent :byte_rate ETA: :eta",
    "tasks" => ":current/:total [:bar] :elapsed",
    "classic" => ":title [:bar] :percent",
    "detailed" => ":title [:bar] :percent :current/:total :rate :elapsed/:eta"
  }
  
  # Sample token data
  SAMPLE_TOKENS = {
    "title" => "Test Task",
    "custom" => "Custom Value",
    "status" => "Processing"
  }
  
  # Helper methods
  def self.create_test_bar(io = TestIO.new, **options)
    defaults = BASIC_CONFIG.merge({output: io})
    Term::Progress::Bar.new(**defaults.merge(options))
  end
  
  def self.create_multi_with_bars(io = TestIO.new, count = 3)
    multi = Term::Progress::Multi.new("Overall [:bar] :percent", output: io)
    
    bars = [] of Term::Progress::Bar
    count.times do |i|
      bar = multi.register("Task #{i + 1} [:bar] :current/:total", total: 100)
      bars << bar
    end
    
    {multi, bars}
  end
  
  def self.advance_bar_to(bar, position, total = nil)
    total ||= bar.total
    steps = (total * position / 100).to_i64
    bar.update(steps)
  end
end