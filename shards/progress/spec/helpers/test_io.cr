class TestIO < IO
  getter output : String
  getter tty : Bool
  
  def initialize(@tty = true)
    @output = ""
  end
  
  def read(slice : Bytes) : Int32
    0
  end
  
  def write(slice : Bytes) : Nil
    @output += String.new(slice)
  end
  
  def tty?
    @tty
  end
  
  def flush
    # no-op
  end
  
  def clear
    @output = ""
  end
end

class ErrorIO < IO
  def read(slice : Bytes) : Int32
    raise IO::Error.new("Simulated read error")
  end
  
  def write(slice : Bytes) : Nil
    raise IO::Error.new("Simulated write error")
  end
  
  def tty?
    true
  end
end