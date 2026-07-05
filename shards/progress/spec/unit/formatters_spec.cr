require "spec"
require "../../src/term-progress"
require "../helpers/test_io"

describe Term::Progress::Formatters do
  describe ".render_bar" do
    it "renders empty bar" do
      result = Term::Progress::Formatters.render_bar(10, 0.0)
      result.should eq("░░░░░░░░░░")
    end
    
    it "renders full bar" do
      result = Term::Progress::Formatters.render_bar(10, 1.0)
      result.should eq("██████████")
    end
    
    it "renders partial bar" do
      result = Term::Progress::Formatters.render_bar(10, 0.5)
      result.should eq("█████░░░░░")
    end
    
    it "renders with custom characters" do
      result = Term::Progress::Formatters.render_bar(5, 0.6, "#", "-")
      result.should eq("###--")
    end
    
    it "handles zero width" do
      result = Term::Progress::Formatters.render_bar(0, 0.5)
      result.should eq("")
    end
  end
  
  describe ".render_blocks" do
    it "renders smooth progress with blocks" do
      result = Term::Progress::Formatters.render_blocks(5, 0.0)
      result.should eq("     ")
      
      result = Term::Progress::Formatters.render_blocks(5, 1.0)
      result.should eq("█████")
    end
    
    it "renders fractional progress" do
      result = Term::Progress::Formatters.render_blocks(4, 0.25)
      result.should eq("█   ")
    end
  end
  
  describe ".format_percentage" do
    it "formats percentage with default precision" do
      result = Term::Progress::Formatters.format_percentage(0.5)
      result.should eq("50%")
      
      result = Term::Progress::Formatters.format_percentage(0.333)
      result.should eq("33%")
    end
    
    it "formats percentage with custom precision" do
      result = Term::Progress::Formatters.format_percentage(0.333, 2)
      result.should eq("33.30%")
    end
  end
  
  describe ".format_fraction" do
    it "formats current/total with proper alignment" do
      result = Term::Progress::Formatters.format_fraction(5_i64, 100_i64)
      result.should eq("  5/100")
      
      result = Term::Progress::Formatters.format_fraction(50_i64, 100_i64)
      result.should eq(" 50/100")
    end
  end
  
  describe ".render_dots" do
    it "renders dots progress" do
      result = Term::Progress::Formatters.render_dots(25_i64, 100_i64, 20)
      result.should eq(".....               ")
    end
    
    it "renders full dots" do
      result = Term::Progress::Formatters.render_dots(100_i64, 100_i64, 10)
      result.should eq("..........")
    end
    
    it "handles zero progress" do
      result = Term::Progress::Formatters.render_dots(0_i64, 100_i64, 5)
      result.should eq("     ")
    end
    
    it "handles zero total" do
      result = Term::Progress::Formatters.render_dots(50_i64, 0_i64, 10)
      result.should eq("          ")
    end
  end
  
  describe ".render_bar with head_char" do
    it "renders bar with head character" do
      result = Term::Progress::Formatters.render_bar(10, 0.5, "█", "░", ">")
      result.should eq("████>░░░░░")
    end
    
    it "renders bar with head at start" do
      result = Term::Progress::Formatters.render_bar(10, 0.1, "█", "░", ">")
      result.should eq(">░░░░░░░░░")
    end
    
    it "renders full bar without head" do
      result = Term::Progress::Formatters.render_bar(5, 1.0, "█", "░", ">")
      result.should eq("█████")
    end
  end
  
  describe "named formats" do
    it "has predefined format templates" do
      Term::Progress::Formatters::FORMATS.has_key?("default").should be_true
      Term::Progress::Formatters::FORMATS.has_key?("minimal").should be_true
      Term::Progress::Formatters::FORMATS.has_key?("download").should be_true
      Term::Progress::Formatters::FORMATS.has_key?("tasks").should be_true
      Term::Progress::Formatters::FORMATS.has_key?("classic").should be_true
      Term::Progress::Formatters::FORMATS.has_key?("detailed").should be_true
    end
    
    it "provides useful format templates" do
      Term::Progress::Formatters::FORMATS["default"].should eq("[:bar] :percent :current/:total")
      Term::Progress::Formatters::FORMATS["minimal"].should eq(":percent :bar")
      Term::Progress::Formatters::FORMATS["download"].should eq("[:bar] :percent :byte_rate ETA: :eta")
    end
  end
  
  describe ".format" do
    it "replaces tokens in template" do
      tokens = {
        "percent" => "50%",
        "bar" => "█████░░░░░",
        "current" => "50",
        "total" => "100"
      }
      
      result = Term::Progress::Formatters.format("[:bar] :percent :current/:total", tokens)
      result.should eq("[█████░░░░░] 50% 50/100")
    end

    it "replaces current total and bar tokens literally" do
      tokens = {
        "current" => "5",
        "total" => "10",
        "bar" => "█████░░░░░"
      }

      result = Term::Progress::Formatters.format(":current/:total [:bar]", tokens)
      result.should eq("5/10 [█████░░░░░]")
    end
    
    it "handles missing tokens gracefully" do
      tokens = {"percent" => "50%"}
      
      result = Term::Progress::Formatters.format(":percent :missing", tokens)
      result.should eq("50% :missing")
    end
    
    it "handles complex token replacement" do
      tokens = {
        "title" => "My Task",
        "bar" => "████████░░",
        "percent" => "80%",
        "rate" => "1.5MB/s",
        "eta" => "00:05"
      }
      
      result = Term::Progress::Formatters.format(":title [:bar] :percent :rate ETA: :eta", tokens)
      result.should eq("My Task [████████░░] 80% 1.5MB/s ETA: 00:05")
    end
    
    it "handles tokens with special characters" do
      tokens = {
        "path" => "/home/user/file (copy).txt",
        "percent" => "45%"
      }
      
      result = Term::Progress::Formatters.format("Processing :path - :percent", tokens)
      result.should eq("Processing /home/user/file (copy).txt - 45%")
    end
  end
end
