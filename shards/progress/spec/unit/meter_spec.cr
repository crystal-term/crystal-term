require "spec"
require "../../src/term-progress"

describe Term::Progress::Meter do
  describe "#format_bytes" do
    it "formats bytes correctly" do
      meter = Term::Progress::Meter.new
      
      meter.format_bytes(0.0).should eq("0 B")
      meter.format_bytes(512.0).should eq("512 B")
      meter.format_bytes(1024.0).should eq("1.0 KB")
      meter.format_bytes(1536.0).should eq("1.5 KB")
      meter.format_bytes(1048576.0).should eq("1.0 MB")
      meter.format_bytes(1073741824.0).should eq("1.0 GB")
    end
  end
  
  describe "#format_time" do
    it "formats time durations correctly" do
      meter = Term::Progress::Meter.new
      
      meter.format_time(nil).should eq("∞")
      meter.format_time(0.0).should eq("--:--")
      meter.format_time(-5.0).should eq("--:--")
      meter.format_time(30.0).should eq("00:30")
      meter.format_time(90.0).should eq("01:30")
      meter.format_time(3661.0).should eq("01:01:01")
    end
    
    it "handles infinite and NaN values" do
      meter = Term::Progress::Meter.new
      
      meter.format_time(Float64::INFINITY).should eq("∞")
      meter.format_time(Float64::NAN).should eq("--:--")
    end
  end
  
  describe "#format_rate" do
    it "formats transfer rates" do
      meter = Term::Progress::Meter.new
      
      meter.format_rate(1024.0).should eq("1.0 KB/s")
      meter.format_rate(1048576.0).should eq("1.0 MB/s")
      meter.format_rate(512.0, "/sec").should eq("512 B/sec")
    end
  end
  
  describe "#eta" do
    it "calculates estimated time remaining" do
      meter = Term::Progress::Meter.new
      
      # Mock some rate data
      meter.update(50)
      sleep(0.01.seconds) # Small delay to establish rate
      meter.update(100)
      
      eta = meter.eta(100, 200)
      eta.should be_a(Float64)
      eta.not_nil!.should be > 0
    end
    
    it "returns nil for invalid conditions" do
      meter = Term::Progress::Meter.new
      
      meter.eta(0, 100).should be_nil
      meter.eta(50, 100).should be_nil # No rate established
    end
  end
  
  describe "#update" do
    it "updates transfer metrics" do
      meter = Term::Progress::Meter.new
      
      meter.rate.should eq(0.0)
      meter.mean_rate.should eq(0.0)
      
      meter.update(100)
      sleep(0.01.seconds)
      meter.update(200)
      
      meter.rate.should be > 0
      meter.mean_rate.should be > 0
    end
  end
  
  describe "#elapsed_time" do
    it "tracks elapsed time" do
      meter = Term::Progress::Meter.new
      
      elapsed = meter.elapsed_time
      elapsed.should be_a(Time::Span)
      elapsed.should be >= Time::Span.zero
    end
  end
end