require "spec"
require "../../src/term-progress"
require "../helpers/test_io"
require "../helpers/fixtures"

describe Term::Progress::Bar do
  describe "#initialize" do
    it "creates a bar with default values" do
      bar = Term::Progress::Bar.new
      
      bar.total.should eq(100)
      bar.current.should eq(0)
      bar.state.should eq(Term::Progress::Bar::State::Running)
    end
    
    it "creates a bar with custom total" do
      bar = Term::Progress::Bar.new(total: 500)
      
      bar.total.should eq(500)
      bar.current.should eq(0)
    end
    
    it "accepts custom format" do
      bar = Term::Progress::Bar.new(format: ":percent [:bar]")
      
      bar.format.should eq(":percent [:bar]")
    end
    
    it "accepts custom width" do
      bar = Term::Progress::Bar.new(width: 50)
      
      bar.width.should eq(50)
    end
    
    it "accepts custom characters" do
      bar = Term::Progress::Bar.new(
        complete_char: "#", 
        incomplete_char: "-", 
        head_char: ">"
      )
      
      bar.complete_char.should eq("#")
      bar.incomplete_char.should eq("-")
      bar.head_char.should eq(">")
    end
    
    it "accepts custom output" do
      io = TestIO.new
      bar = Term::Progress::Bar.new(output: io)
      
      bar.output.should eq(io)
    end
    
    it "handles nil head_char" do
      bar = Term::Progress::Bar.new(head_char: nil)
      
      bar.head_char.should be_nil
    end
  end
  
  describe "#advance" do
    it "increases current by 1" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.advance
      bar.current.should eq(1)
      
      bar.advance(5)
      bar.current.should eq(6)
    end
    
    it "doesn't exceed total" do
      bar = Term::Progress::Bar.new(total: 10)
      
      bar.advance(15)
      bar.current.should eq(10)
    end
    
    it "finishes when reaching total" do
      bar = Term::Progress::Bar.new(total: 1)
      
      bar.advance
      bar.finished?.should be_true
    end
  end
  
  describe "#update" do
    it "sets current to specific value" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.update(50)
      bar.current.should eq(50)
    end
    
    it "clamps value to valid range" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.update(-10)
      bar.current.should eq(0)
      
      bar.update(150)
      bar.current.should eq(100)
    end
  end
  
  describe "#ratio" do
    it "calculates completion ratio" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.ratio.should eq(0.0)
      
      bar.update(25)
      bar.ratio.should eq(0.25)
      
      bar.update(100)
      bar.ratio.should eq(1.0)
    end
    
    it "handles zero total" do
      bar = Term::Progress::Bar.new(total: 0)
      
      bar.ratio.should eq(0.0)
    end
  end
  
  describe "#finish" do
    it "sets state to finished" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.finish
      bar.finished?.should be_true
      bar.current.should eq(100)
    end
  end
  
  describe "#stop" do
    it "sets state to stopped" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.stop
      bar.stopped?.should be_true
    end
  end
  
  describe "#reset" do
    it "resets bar to initial state" do
      bar = Term::Progress::Bar.new(total: 100)
      bar.advance(50)
      bar.finish
      
      bar.reset
      
      bar.current.should eq(0)
      bar.running?.should be_true
      bar.finished?.should be_false
    end
  end
  
  describe "state methods" do
    it "correctly reports states" do
      bar = Term::Progress::Bar.new(total: 100)
      
      bar.running?.should be_true
      bar.finished?.should be_false
      bar.stopped?.should be_false
      
      bar.finish
      bar.running?.should be_false
      bar.finished?.should be_true
      bar.stopped?.should be_false
      
      bar.reset
      bar.stop
      bar.running?.should be_false
      bar.finished?.should be_false
      bar.stopped?.should be_true
    end
  end
  
  describe "#resize" do
    it "resizes bar width" do
      bar = Term::Progress::Bar.new(width: 20)
      
      bar.width.should eq(20)
      bar.resize(40)
      bar.width.should eq(40)
    end
    
    it "recalculates width when nil provided" do
      bar = Term::Progress::Bar.new(width: 20)
      
      bar.resize(nil)
      # Width should be recalculated (not 20 anymore)
      bar.width.should_not eq(20)
    end
  end
  
  describe "#log" do
    it "logs message to output" do
      io = TestIO.new
      bar = Term::Progress::Bar.new(output: io)
      
      bar.log("Test message")
      io.output.should contain("Test message")
    end
    
    it "works when attached to multi" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(nil, io)
      bar = multi.register("Task", 100)
      
      # Should not crash
      bar.log("Multi message")
    end
  end
  
  describe "#update_tokens" do
    it "updates custom tokens" do
      bar = Term::Progress::Bar.new(format: ":title [:bar] :status")
      
      bar.update_tokens(title: "My Task", status: "Processing")
      
      bar.tokens["title"].should eq("My Task")
      bar.tokens["status"].should eq("Processing")
    end
    
    it "updates existing tokens" do
      bar = Term::Progress::Bar.new(format: ":title [:bar]")
      bar.update_tokens(title: "First")
      
      bar.tokens["title"].should eq("First")
      
      bar.update_tokens(title: "Second")
      bar.tokens["title"].should eq("Second")
    end
  end
  
  describe "#attach_to" do
    it "attaches to multi progress" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(nil, io)
      bar = Term::Progress::Bar.new
      
      bar.attach_to(multi, 1)
      
      # Should not crash and bar should be attached
      bar.advance(10)
    end
  end
  
  describe "thread safety" do
    it "handles concurrent advances" do
      bar = Term::Progress::Bar.new(total: 1000)
      
      # Simulate concurrent updates
      spawn { 50.times { bar.advance(2) } }
      spawn { 50.times { bar.advance(3) } }
      spawn { 50.times { bar.advance(5) } }
      
      # Give time for spawns to complete
      sleep(0.1.seconds)
      
      # Should reach expected total without race conditions
      bar.current.should eq(500) # 50*(2+3+5) = 500
    end
  end
  
  describe "non-TTY behavior" do
    it "works with non-TTY output" do
      io = TestIO.new(tty: false)
      bar = Term::Progress::Bar.new(output: io)
      
      # Should not crash
      bar.advance(50)
      bar.finish("Done")
    end
  end
  
  describe "edge cases" do
    it "handles zero total" do
      bar = Term::Progress::Bar.new(total: 0)
      
      bar.ratio.should eq(0.0)
      bar.advance(10)
      bar.current.should eq(0) # Can't exceed total
    end
    
    it "handles negative advance" do
      bar = Term::Progress::Bar.new(total: 100)
      bar.advance(50)
      
      bar.advance(-10) # Negative advance
      bar.current.should eq(40) # Goes backwards with negative
    end
    
    it "handles finish with message" do
      io = TestIO.new
      bar = Term::Progress::Bar.new(output: io)
      
      bar.finish("Custom finish message")
      
      bar.finished?.should be_true
      io.output.should contain("Custom finish message")
    end
    
    it "handles stop with message" do
      io = TestIO.new
      bar = Term::Progress::Bar.new(output: io)
      
      bar.stop("Custom stop message")
      
      bar.stopped?.should be_true
      io.output.should contain("Custom stop message")
    end
    
    it "ignores operations when stopped" do
      bar = Term::Progress::Bar.new(total: 100)
      bar.stop
      
      original_current = bar.current
      bar.advance(10)
      bar.current.should eq(original_current) # No change
    end
    
    it "ignores operations when finished" do
      bar = Term::Progress::Bar.new(total: 100)
      bar.finish
      
      original_current = bar.current
      bar.advance(10)
      bar.current.should eq(original_current) # No change
    end
  end
end