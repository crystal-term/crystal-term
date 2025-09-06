module Term
  module Progress
    module Formatters
      extend self
      
      FORMATS = {
        "default" => "[:bar] :percent :current/:total",
        "minimal" => ":percent :bar",
        "download" => "[:bar] :percent :byte_rate ETA: :eta",
        "tasks" => ":current/:total [:bar] :elapsed",
        "classic" => ":title [:bar] :percent",
        "detailed" => ":title [:bar] :percent :current/:total :rate :elapsed/:eta"
      }
      
      def format(template : String, tokens : Hash(String, String)) : String
        result = template.dup
        tokens.each do |key, value|
          result = result.gsub(/:#{key}/, value)
        end
        result
      end
      
      def render_bar(width : Int32, ratio : Float64, complete_char = "█", incomplete_char = "░", head_char = nil)
        return "" if width <= 0
        
        filled_width = (width * ratio).to_i
        remaining_width = width - filled_width
        
        filled_part = complete_char * filled_width
        empty_part = incomplete_char * remaining_width
        
        if head_char && filled_width < width && filled_width > 0
          if filled_width > 0
            filled_part = complete_char * (filled_width - 1) + head_char
          else
            empty_part = head_char + incomplete_char * (remaining_width - 1)
          end
        end
        
        filled_part + empty_part
      end
      
      def render_dots(current : Int64, total : Int64, width = 50)
        ratio = total > 0 ? current.to_f / total : 0.0
        dots_count = (width * ratio).to_i
        
        ("." * dots_count).ljust(width, ' ')
      end
      
      def render_blocks(width : Int32, ratio : Float64)
        return "" if width <= 0
        
        blocks = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
        
        filled_width = width * ratio
        full_blocks = filled_width.to_i
        fractional = filled_width - full_blocks
        
        result = "█" * full_blocks
        
        if full_blocks < width
          fraction_index = (fractional * (blocks.size - 1)).round.to_i
          if fraction_index > 0
            result += blocks[fraction_index]
            result += " " * (width - full_blocks - 1)
          else
            result += " " * (width - full_blocks)
          end
        end
        
        result.ljust(width, ' ')[0...width]
      end
      
      def format_percentage(ratio : Float64, precision = 0) : String
        percentage = (ratio * 100).round(precision)
        if precision == 0
          "#{percentage.to_i}%"
        else
          "%.#{precision}f%%" % percentage
        end
      end
      
      def format_fraction(current : Int64, total : Int64) : String
        total_width = total.to_s.size
        "%#{total_width}d/%d" % [current, total]
      end
    end
  end
end