require "spec"
require "../../src/term-progress"
require "../helpers/test_io"

describe Term::Progress::Multi do
  describe "basic functionality" do
    it "creates empty multi" do
      io = TestIO.new
      multi = Term::Progress::Multi.new(nil, io)
      
      multi.empty?.should be_true
      multi.size.should eq(0)
    end
    
    it "creates multi with message" do
      io = TestIO.new
      multi = Term::Progress::Multi.new("Test", io)
      
      multi.size.should eq(1)
    end
  end
end