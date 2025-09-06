module Term
  module Progress
    class Meter
      BYTE_UNITS = %w[B KB MB GB TB PB]
      
      getter :rate, :mean_rate, :samples
      
      @start_time : Time
      @last_time : Time
      @samples : Array(Float64)
      @total_transferred : Int64
      @last_transferred : Int64
      
      def initialize
        @start_time = Time.utc
        @last_time = @start_time
        @samples = [] of Float64
        @total_transferred = 0_i64
        @last_transferred = 0_i64
        @rate = 0.0
        @mean_rate = 0.0
      end
      
      def update(transferred : Int64)
        now = Time.utc
        elapsed = (now - @last_time).total_seconds
        
        return if elapsed <= 0
        
        delta = transferred - @last_transferred
        current_rate = delta / elapsed
        
        @samples << current_rate
        @samples.shift if @samples.size > 10
        
        @rate = current_rate
        @mean_rate = @samples.sum / @samples.size
        
        @total_transferred = transferred
        @last_transferred = transferred
        @last_time = now
      end
      
      def elapsed_time
        Time.utc - @start_time
      end
      
      def eta(current : Int64, total : Int64)
        return nil if current <= 0 || @mean_rate <= 0
        
        remaining = total - current
        remaining / @mean_rate
      end
      
      def format_rate(rate : Float64, suffix = "/s")
        format_bytes(rate) + suffix
      end
      
      def format_bytes(bytes : Float64)
        return "0 B" if bytes <= 0
        
        unit_index = 0
        size = bytes.abs
        
        while size >= 1024 && unit_index < BYTE_UNITS.size - 1
          size /= 1024.0
          unit_index += 1
        end
        
        if unit_index == 0
          "#{size.to_i} #{BYTE_UNITS[unit_index]}"
        else
          "#{size.round(1)} #{BYTE_UNITS[unit_index]}"
        end
      end
      
      def format_time(seconds : Float64?)
        return "∞" if seconds.nil? || seconds.infinite?
        return "--:--" if seconds.nan? || seconds <= 0
        
        total_seconds = seconds.to_i
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        secs = total_seconds % 60
        
        if hours > 0
          "%02d:%02d:%02d" % [hours, minutes, secs]
        else
          "%02d:%02d" % [minutes, secs]
        end
      end
    end
  end
end