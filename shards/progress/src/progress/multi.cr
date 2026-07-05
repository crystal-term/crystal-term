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
      
      # Wrappers for first/middle/last/single rows (tree-like)
      @wrapper_first : String
      @wrapper_middle : String
      @wrapper_last : String
      @wrapper_single : String
      
      def initialize(message = nil, output : IO? = nil, **options)
        @output = output || options[:output]? || STDERR
        @bars = [] of Bar
        @top_bar = nil
        @mutex = Mutex.new
        @lines = [] of String
        @max_rows = 0
        
        # Configure wrappers; default to a tree-like structure
        @wrapper_first = (options[:wrapper_first]? || "├── :content").to_s
        @wrapper_middle = (options[:wrapper_middle]? || "├── :content").to_s
        @wrapper_last = (options[:wrapper_last]? || "└── :content").to_s
        @wrapper_single = (options[:wrapper_single]? || "└── :content").to_s
        
        if message
          # Create top bar directly
          @top_bar = Bar.new(format: message, output: @output)
          @bars << @top_bar.not_nil!
        end
      end
      
      def register(pattern_or_bar, total = 100_i64, observable = true)
        bar = case pattern_or_bar
              when String
                Bar.new(format: pattern_or_bar, total: total, output: @output)
              when Bar
                pattern_or_bar
              else
                raise ArgumentError.new("Expected a format string or Bar, got: #{pattern_or_bar.class}")
              end

        @mutex.synchronize do
          row = next_row
          bar.attach_to(self, row)

          @bars << bar
          @lines << ""

          # Re-render all lines so wrappers update (e.g., last -> middle when adding)
          clear_all_lines
          render_all_lines
          @output.flush
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
      
      
      
      # Remove a bar from this Multi and re-index remaining bars.
      def remove(bar : Bar)
        @mutex.synchronize do
          index = @bars.index(bar)
          return unless index
          # Detach the bar
          bar.detach if bar.responds_to?(:detach)
          
          @bars.delete_at(index)
          @lines.delete_at(index) if index < @lines.size
          
          # Reassign rows for remaining bars
          child_bars.each_with_index do |b, i|
            new_row = @top_bar ? i + 2 : i + 1
            b.attach_to(self, new_row)
          end
          
          clear_all_lines
          render_all_lines
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
      
      # Wrap bar content based on position to build a tree-like structure.
      private def wrap_content(row : Int32, content : String) : String
        # Top bar (if any) should not be wrapped
        if @top_bar && row == 1
          return content
        end
        
        # Determine index and count among child bars
        child_count = child_bars.size
        if child_count <= 0
          return content
        end
        child_row_index = @top_bar ? row - 2 : row - 1  # 0-based among children
        
        template = if child_count == 1
          @wrapper_single
        elsif child_row_index == 0
          @wrapper_first
        elsif child_row_index == child_count - 1
          @wrapper_last
        else
          @wrapper_middle
        end
        
        if template.includes?(":content")
          template.gsub(":content", content)
        else
          template + content
        end
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
          wrapped = wrap_content(index + 1, line)
          @output.print wrapped
          @output.print Term::Cursor.clear_line_after
          @output.print "\n" unless index == @lines.size - 1
        end
        @max_rows = @lines.size
      end
      
      def render_line(row : Int32, content : String, final = false)
        @mutex.synchronize do
          return unless tty?
          
          line_index = (@top_bar ? row - 2 : row - 1)
          return if line_index < 0 || line_index >= @lines.size
          
          @lines[line_index] = content
          
          # Move the cursor to the exact row relative to the top of the block
          if @max_rows > 0
            @output.print Term::Cursor.save
            # Go to top of block
            @output.print Term::Cursor.up(@max_rows - 1) if @max_rows > 1
            # Move down to target row (row is 1-based)
            @output.print Term::Cursor.down(line_index) if line_index > 0
          end
          
          wrapped = wrap_content(@top_bar ? line_index + 2 : line_index + 1, content)
          @output.print "\r#{wrapped}"
          @output.print Term::Cursor.clear_line_after
          
          if @max_rows > 0
            @output.print Term::Cursor.restore
          elsif line_index == @lines.size - 1
            # Last bar, move to next line if not final
            @output.print "\n" unless final
          end
          
          @max_rows = Math.max(@max_rows, line_index + 1)
          @output.flush
        end
      end
    end
  end
end
