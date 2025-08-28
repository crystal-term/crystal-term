require "spec"
require "../../src/term-progress"
require "../helpers/test_io"
require "../helpers/fixtures"

describe Term::Progress::Multi do
  describe "#initialize" do
    it "creates empty multi without message" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      multi.empty?.should be_true
      multi.size.should eq(0)
    end
    
    it "creates multi with top-level message" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall [:bar] :percent", io)
      
      multi.empty?.should be_false
      multi.size.should eq(1)
    end
    
    it "accepts custom output" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(nil, io)
      
      multi.output.should eq(io)
    end
  end
  
  describe "#register" do
    it "registers bar with format string" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar = multi.register("Task [:bar] :percent", total: 100)
      
      bar.should be_a(Term::Progress::Bar)
      multi.size.should eq(1)
    end
    
    it "registers existing bar instance" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      existing_bar = Term::Progress::Bar.new(total: 50)
      
      bar = multi.register(existing_bar)
      
      bar.should eq(existing_bar)
      multi.size.should eq(1)
    end
    
    it "registers bar with block" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar = multi.register("Task [:bar] :percent", total: 100) do |b|
        b.update_tokens(title: "Test")
      end
      
      bar.tokens["title"].should eq("Test")
    end
    
    it "rejects invalid bar types" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      expect_raises(ArgumentError, /Expected a format string or Bar/) do
        multi.register(123)
      end
    end
  end
  
  describe "enumerable interface" do
    it "iterates over bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      bars = [] of Term::Progress::Bar
      multi.each { |bar| bars << bar }
      
      bars.size.should eq(2)
      bars.should contain(bar1)
      bars.should contain(bar2)
    end
    
    it "reports size correctly" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      multi.size.should eq(0)
      multi.register("Task 1", total: 100)
      multi.size.should eq(1)
      multi.register("Task 2", total: 100)
      multi.size.should eq(2)
    end
    
    it "reports empty state" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      multi.empty?.should be_true
      multi.register("Task 1", total: 100)
      multi.empty?.should be_false
    end
  end
  
  describe "bulk operations" do
    it "advances all bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.advance_all(10)
      
      bar1.current.should eq(10)
      bar2.current.should eq(10)
    end
    
    it "finishes all bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.finish_all("Complete!")
      
      bar1.finished?.should be_true
      bar2.finished?.should be_true
    end
    
    it "stops all bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.stop_all("Stopped")
      
      bar1.stopped?.should be_true
      bar2.stopped?.should be_true
    end
    
    it "resets all bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      bar1.advance(50)
      bar2.advance(75)
      bar1.finish
      
      multi.reset_all
      
      bar1.current.should eq(0)
      bar2.current.should eq(0)
      bar1.running?.should be_true
    end
  end
  
  describe "state queries" do
    it "checks if all bars are done" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall", output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.done?.should be_false
      
      bar1.finish
      multi.done?.should be_false
      
      bar2.finish
      multi.done?.should be_true
    end
    
    it "checks if any bar is finished" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall", output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.any_finished?.should be_false
      
      bar1.finish
      multi.any_finished?.should be_true
    end
    
    it "checks if any bar is stopped" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall", output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.any_stopped?.should be_false
      
      bar1.stop
      multi.any_stopped?.should be_true
    end
  end
  
  describe "#progress_ratio" do
    it "calculates overall progress ratio" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall", output: io)
      
      bar1 = multi.register("Task 1", total: 100)
      bar2 = multi.register("Task 2", total: 200)
      
      multi.progress_ratio.should eq(0.0)
      
      bar1.update(50)   # 50/100 = 50% of bar1
      bar2.update(100)  # 100/200 = 50% of bar2
      
      # Total: (50 + 100) / (100 + 200) = 150/300 = 0.5
      multi.progress_ratio.should eq(0.5)
    end
    
    it "handles empty multi" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      multi.progress_ratio.should eq(0.0)
    end
    
    it "handles zero totals" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall", output: io)
      
      bar1 = multi.register("Task 1", total: 0)
      bar2 = multi.register("Task 2", total: 100)
      
      bar2.update(50)
      multi.progress_ratio.should eq(0.5) # 50/100
    end
  end
  
  describe "#log" do
    it "logs message and preserves bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      bar = multi.register("Task [:bar] :percent", total: 100)
      bar.advance(50)
      
      initial_output = io.output
      multi.log("Test message")
      
      # Should contain the logged message
      io.output.should contain("Test message")
      # Should be longer than initial (added content)
      io.output.size.should be > initial_output.size
    end
    
    it "works with non-TTY output" do
      io = TestIO.new(tty: false)
      multi = Term::Progress::Multi.new(output: io)
      
      multi.log("Non-TTY message")
      # Should not crash on non-TTY
    end
  end
  
  describe "#synchronize" do
    it "provides thread synchronization" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(output: io)
      
      result = multi.synchronize do
        "synchronized"
      end
      
      result.should eq("synchronized")
    end
  end
  
  describe "top bar vs child bars" do
    it "distinguishes top bar from child bars" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Overall [:bar] :percent", output: io)
      
      child1 = multi.register("Child 1", total: 100)
      child2 = multi.register("Child 2", total: 100)
      
      multi.size.should eq(3) # Top bar + 2 child bars
      
      # Only child bars should count toward done? status
      child1.finish
      multi.done?.should be_false
      
      child2.finish
      multi.done?.should be_true
    end
  end
end