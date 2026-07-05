# Spinner integration for Term::Progress::Bar with Term::Spinner formats.
#
# Loaded by default via `term-progress`. Use by including `:spinner` in the bar
# format. You can override frames/interval via options:
#   Term::Progress::Bar.new(
#     format: ":spinner [:bar] :percent",
#     spinner_format: :dots,                      # or :classic, :pulse, etc.
#     # or
#     spinner_frames: ["-", "\\", "|", "/"],
#     spinner_interval: 100                       # ms-like (10x multiplexed)
#   )

module Term
  module Progress
    class Bar
      # Frames and timer for spinner animation
      @spinner_frames : Array(String)?
      @spinner_interval : Time::Span?
      @spinner_index : Int32 = 0
      @spinner_fiber : Fiber?

      # Enable animated spinner token inside this bar.
      #
      # - Include `:spinner` in the bar `format` string to display.
      # - Frames are sourced from Term::Spinner::FORMATS by name (default: :classic).
      # - You can also provide custom `frames:` and/or `interval:`.
      #
      # Examples:
      #   bar = Term::Progress::Bar.new(format: ":spinner [:bar] :percent")
      #   bar.enable_spinner(:dots)
      #
      #   bar.enable_spinner(frames: ["-", "\\", "|", "/"], interval: 100.milliseconds)
      def enable_spinner(format : String | Symbol = :classic, frames : Array(String)? = nil, interval : (Int32 | Time::Span)? = nil)
        # Determine frames/interval from explicit args or Term::Spinner presets
        chosen_frames = frames
        chosen_interval = interval

        unless chosen_frames
          preset = ::Term::Spinner::FORMATS[format.to_s]?
          if preset
            chosen_frames = preset[:frames]
            chosen_interval ||= preset[:interval]
          else
            # Fallback to classic frames if format not found
            classic = ::Term::Spinner::FORMATS["classic"]
            chosen_frames = classic[:frames]
            chosen_interval ||= classic[:interval]
          end
        end

        # Normalize interval semantics to a Time::Span identical to Spinner
        actual_interval = case chosen_interval
                          when Time::Span
                            chosen_interval
                          when Int32
                            (1000 // chosen_interval).milliseconds
                          when Nil
                            # Default to Spinner classic if nothing provided
                            100.milliseconds
                          end

        @spinner_frames = chosen_frames
        @spinner_interval = actual_interval
        @spinner_index = 0

        # Seed token to avoid showing literal :spinner before first tick
        @tokens["spinner"] = ""

        # Start animation fiber
        start_spinner_fiber
      end

      # Disable spinner animation and clear token
      def disable_spinner
        if fiber = @spinner_fiber
          @spinner_fiber = nil
          # No direct way to kill a fiber; it exits naturally on next tick
          # because @spinner_fiber becomes nil. We also set running? guard.
        end
        @spinner_frames = nil
        @spinner_interval = nil
        @spinner_index = 0
        @tokens["spinner"] = ""
      end

      private def start_spinner_fiber
        frames = @spinner_frames
        interval = @spinner_interval
        return unless frames && interval

        # Avoid starting multiple fibers
        return if @spinner_fiber

        @spinner_fiber = spawn do
          # Periodically update spinner token while the bar is running
          while running? && @spinner_fiber
            frame = frames[@spinner_index]
            @spinner_index = (@spinner_index + 1) % frames.size

            # Update token and re-render safely
            @mutex.synchronize do
              # Preserve any external token overrides but typically we own it
              @tokens["spinner"] = frame
              render
            end

            sleep interval
          end
        end
      end
    end
  end
end
