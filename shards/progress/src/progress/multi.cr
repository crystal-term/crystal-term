module Term
  module Progress
    class Multi
      include Enumerable(Bar)
      
      delegate :each, :empty?, :size, to: @bars
      
      getter :output, :bars
      
      @output : IO
      @bars : Array(Bar)
      @top_bar : Bar?
      @mutex : Mutex
      @lines : Array(String)
      @max_rows : Int32
      
      def initialize(message = nil, output : IO? = nil, **options)
        @output = output || options[:output]? || STDERR
        @bars = [] of Bar
        @top_bar = nil
        @mutex = Mutex.new
        @lines = [] of String
        @max_rows = 0
        
        if message
          # Create top bar directly
          @top_bar = Bar.new(format: message, output: @output)
          @bars << @top_bar.not_nil!
        end
      end
      
      def register(pattern_or_bar, total = 100_i64, observable = true)
        case pattern_or_bar
        when String
          bar = Bar.new(format: pattern_or_bar, total: total, output: @output)
        when Bar
          bar = pattern_or_bar
        else
          raise ArgumentError.new("Expected a format string or Bar, got: #{pattern_or_bar.class}")
        end
        
        row = next_row
        bar.attach_to(self, row)
        
        @bars << bar
        @lines << ""
        
        if @top_bar
          # Bars will render naturally when updated
        end
        
        bar
      end
      
      def register(pattern_or_bar, total = 100_i64, observable = true, &block : Bar ->)
        bar = register(pattern_or_bar, total, observable)
        yield bar
        bar
      end
      
      def log(message : String)
        @mutex.synchronize do
          clear_all_lines
          @output.puts message
          render_all_lines
          @output.flush
        end
      end
      
      def render_line(row : Int32, content : String, final = false)
        @mutex.synchronize do
          return unless tty?
          
          line_index = row - 1
          return if line_index < 0 || line_index >= @lines.size
          
          @lines[line_index] = content
          
          # Move to the correct line and render
          if @max_rows > 0
            lines_to_move_up = @max_rows - row
            @output.print Term::Cursor.save
            @output.print Term::Cursor.up(lines_to_move_up) if lines_to_move_up > 0
          end
          
          @output.print "\r#{content}"
          @output.print Term::Cursor.clear_line_after
          
          if @max_rows > 0
            @output.print Term::Cursor.restore
          elsif row == @bars.size
            # Last bar, move to next line if not final
            @output.print "\n" unless final
          end
          
          @max_rows = Math.max(@max_rows, row)
          @output.flush
        end
      end
      
      def advance_all(by : Int64 = 1)
        @bars.each(&.advance(by))
      end
      
      def finish_all(message = "")
        @bars.each(&.finish(message))
      end
      
      def stop_all(message = "")
        @bars.each(&.stop(message))
      end
      
      def reset_all
        @bars.each(&.reset)
        @lines.clear
        @max_rows = 0
      end
      
      def done?
        child_bars.all?(&.finished?)
      end
      
      def any_finished?
        child_bars.any?(&.finished?)
      end
      
      def any_stopped?
        child_bars.any?(&.stopped?)
      end
      
      def progress_ratio
        return 0.0 if child_bars.empty?
        
        total_progress = child_bars.sum(&.current)
        total_max = child_bars.sum(&.total)
        
        total_max > 0 ? total_progress.to_f / total_max : 0.0
      end
      
      def synchronize(&block)
        @mutex.synchronize { yield }
      end
      
      private def create_bar(pattern_or_bar, options)
        case pattern_or_bar
        when String
          Bar.new(**options.merge({format: pattern_or_bar}))
        when Bar
          pattern_or_bar
        else
          raise ArgumentError.new("Expected a format string or Bar, got: #{pattern_or_bar.class}")
        end
      end
      
      private def next_row
        @bars.size + 1
      end
      
      private def child_bars
        @top_bar ? @bars[1..] : @bars
      end
      
      private def tty?
        @output.responds_to?(:tty?) ? @output.tty? : false
      end
      
      private def clear_all_lines
        return unless tty?
        
        if @max_rows > 0
          @output.print Term::Cursor.up(@max_rows - 1)
          @max_rows.times do
            @output.print Term::Cursor.clear_line
            @output.print Term::Cursor.down(1) unless @max_rows == 1
          end
          @output.print Term::Cursor.up(@max_rows - 1)
        end
      end
      
      private def render_all_lines
        return unless tty?
        
        @lines.each_with_index do |line, index|
          @output.print line
          @output.print Term::Cursor.clear_line_after
          @output.print "\n" unless index == @lines.size - 1
        end
      end
    end
  end
end