module Term
  module Progress
    class Bar
      enum State
        Running
        Finished
        Stopped
      end
      
      DEFAULT_WIDTH = 30
      DEFAULT_FORMAT = "[:bar] :percent :current/:total"
      
      getter :total, :current, :width, :format
      getter :complete_char, :incomplete_char, :head_char
      getter :output, :tokens, :state
      getter :meter
      
      @total : Int64
      @current : Int64
      @width : Int32
      @format : String
      @complete_char : String
      @incomplete_char : String
      @head_char : String?
      @output : IO
      @tokens : Hash(String, String)
      @format_tokens : Set(String)
      @state : State
      @meter : Meter
      @multi : Multi?
      @row : Int32?
      @mutex : Mutex
      @first_render : Bool
      
      def initialize(total : Int64 = 100, **options)
        @total = total
        @current = 0_i64
        @format = options[:format]?.try(&.to_s) || DEFAULT_FORMAT
        @format_tokens = extract_format_tokens(@format)
        @width = options[:width]? || calculate_width
        
        @complete_char = options[:complete_char]?.try(&.to_s) || "█"
        @incomplete_char = options[:incomplete_char]?.try(&.to_s) || "░"
        @head_char = options[:head_char]?.try(&.to_s)
        
        @output = options[:output]? || STDERR
        @tokens = {} of String => String
        @state = State::Running
        @meter = Meter.new
        @multi = nil
        @row = options[:row]?
        @mutex = Mutex.new
        @first_render = true
        
        # If the format includes :spinner, auto-enable spinner animation.
        if @format.includes?(":spinner")
          # Optional overrides
          spinner_format = (options[:spinner_format]? || :classic).to_s
          spinner_frames = options[:spinner_frames]?.as?(Array(String))
          interval_int = options[:spinner_interval]?.as?(Int32)
          interval_span = options[:spinner_interval]?.as?(Time::Span)
          interval : (Int32 | Time::Span | Nil) = interval_span || interval_int

          # Method provided by spinner_integration
          enable_spinner(spinner_format, spinner_frames, interval)
        end

        update_tokens
      end
      
      def attach_to(multi : Multi, row : Int32)
        @multi = multi
        @row = row
      end
      
      # Detach this bar from its Multi orchestrator
      def detach
        @multi = nil
        @row = nil
      end
      
      def advance(by : Int64 = 1)
        @mutex.synchronize do
          return if finished? || stopped?
          
          @current = Math.min(@current + by, @total)
          @meter.update(@current)
          update_tokens
          render
        end
        
        finish if @current >= @total
      end
      
      def update(current : Int64)
        @mutex.synchronize do
          return if finished? || stopped?
          
          @current = Math.min(Math.max(current, 0_i64), @total)
          @meter.update(@current)
          update_tokens
          render
        end
        
        finish if @current >= @total
      end
      
      def ratio
        return 0.0 if @total <= 0
        @current.to_f / @total
      end
      
      def finished?
        @state == State::Finished
      end
      
      def stopped?
        @state == State::Stopped
      end
      
      def running?
        @state == State::Running
      end
      
      def finish(message = "")
        @mutex.synchronize do
          return if finished? || stopped?
          
          @current = @total
          @state = State::Finished
          update_tokens
          render(final: true, message: message)
        end
      end
      
      def stop(message = "")
        @mutex.synchronize do
          return if finished? || stopped?
          
          @state = State::Stopped
          render(final: true, message: message)
        end
      end
      
      def reset
        @mutex.synchronize do
          @current = 0_i64
          @state = State::Running
          @meter = Meter.new
          @first_render = true
          update_tokens
        end
      end
      
      def resize(width : Int32? = nil)
        @width = width || calculate_width
        update_tokens
        render if running?
      end
      
      def log(message : String)
        if multi = @multi
          multi.log(message)
        else
          clear_line
          @output.puts message
          render
        end
      end
      
      def update_tokens(**new_tokens)
        @mutex.synchronize do
          @tokens.merge!(new_tokens.to_h.transform_keys(&.to_s).transform_values(&.to_s))
          update_tokens
        end
      end
      
      private def update_tokens
        bar_width = nil
        if uses_format_token?("bar") || uses_format_token?("blocks") || uses_format_token?("dots")
          bar_width = calculate_bar_width
        end
        
        if uses_format_token?("bar")
          @tokens["bar"] = Formatters.render_bar(bar_width.not_nil!, ratio, @complete_char, @incomplete_char, @head_char)
        end
        if uses_format_token?("blocks")
          @tokens["blocks"] = Formatters.render_blocks(bar_width.not_nil!, ratio)
        end
        if uses_format_token?("dots")
          @tokens["dots"] = Formatters.render_dots(@current, @total, bar_width.not_nil!)
        end
        if uses_format_token?("spinner")
          # Optional spinner token (set by spinner integration). Default to empty.
          @tokens["spinner"] = @tokens["spinner"]? || ""
        end
        if uses_format_token?("percent")
          @tokens["percent"] = Formatters.format_percentage(ratio)
        end
        if uses_format_token?("current")
          @tokens["current"] = @current.to_s
        end
        if uses_format_token?("total")
          @tokens["total"] = @total.to_s
        end
        if uses_format_token?("fraction")
          @tokens["fraction"] = Formatters.format_fraction(@current, @total)
        end
        if uses_format_token?("elapsed")
          @tokens["elapsed"] = @meter.format_time(@meter.elapsed_time.total_seconds)
        end
        
        if uses_format_token?("eta")
          if eta_seconds = @meter.eta(@current, @total)
            @tokens["eta"] = @meter.format_time(eta_seconds)
          else
            @tokens["eta"] = "--:--"
          end
        end
        
        if uses_format_token?("rate")
          @tokens["rate"] = "%.1f/s" % @meter.rate
        end
        if uses_format_token?("mean_rate")
          @tokens["mean_rate"] = "%.1f/s" % @meter.mean_rate
        end
        if uses_format_token?("byte_rate")
          @tokens["byte_rate"] = @meter.format_rate(@meter.rate)
        end
        if uses_format_token?("mean_byte_rate")
          @tokens["mean_byte_rate"] = @meter.format_rate(@meter.mean_rate)
        end
      end
      
      private def render(final = false, message = "")
        return unless tty?
        
        display = Formatters.format(@format, @tokens)
        display += " #{message}" unless message.empty?
        
        if multi = @multi
          multi.render_line(@row.not_nil!, display, final)
        else
          if @first_render
            @output.print display
            @first_render = false
          else
            # Clear the line completely using proper width calculation
            clear_line
            @output.print display
          end
          
          if final
            @output.print "\n"
          end
          
          @output.flush
        end
      end
      
      private def clear_line
        return unless tty?
        
        if multi = @multi
          # Multi handles line clearing
        else
          @output.print "\r\e[2K"
          @output.flush
        end
      end
      
      private def tty?
        @output.responds_to?(:tty?) ? @output.tty? : false
      end
      
      private def calculate_width
        if format_width = Formatters::FORMATS[@format]?
          DEFAULT_WIDTH
        else
          terminal_width = Term::Screen.width
          # Reserve space for other format elements
          Math.max(DEFAULT_WIDTH, terminal_width - 50)
        end
      end
      
      private def calculate_bar_width
        # Calculate available width for the bar itself within the format
        sample_tokens = @tokens.dup
        # Clear ALL bar-related tokens to exclude them from width calculation
        sample_tokens["bar"] = ""
        sample_tokens["blocks"] = ""
        sample_tokens["dots"] = ""
        
        format_without_bar = Formatters.format(@format, sample_tokens)
        terminal_width = Term::Screen.width
        
        available_width = terminal_width - format_without_bar.size - 2
        Math.max(10, Math.min(available_width, @width))
      end

      private def extract_format_tokens(format : String) : Set(String)
        tokens = Set(String).new
        format.scan(/:(\w+)/) do |match|
          tokens << match[1]
        end
        tokens
      end

      private def uses_format_token?(name : String) : Bool
        @format_tokens.includes?(name)
      end
    end
  end
end
