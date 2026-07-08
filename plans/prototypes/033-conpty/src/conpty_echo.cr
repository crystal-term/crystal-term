# Plan 033 ConPTY prototype — Windows only.
#
# Spawns `cmd /c echo ok` under CreatePseudoConsole, pumps the output
# pipe into Term::VT::Screen, prints the snapshot.
#
# Written against:
#   https://learn.microsoft.com/en-us/windows/console/creating-a-pseudoconsole-session
#   microsoft/terminal samples/ConPTY/EchoCon
#
# Status: UNTESTED on a real Windows host (spike workstation is macOS).

{% unless flag?(:win32) %}
  {% raise "conpty_echo is Windows/ConPTY-only. Build on Windows with Crystal targeting win32." %}
{% end %}

require "term-vt"

# Minimal ConPTY + process-attribute bindings not yet in Crystal's LibC.
@[Link("kernel32")]
lib LibConPTY
  alias HANDLE = Void*
  alias BOOL = LibC::BOOL
  alias DWORD = LibC::DWORD
  # HRESULT is not in Crystal's LibC; Win32 uses LONG (Int32).
  alias HRESULT = Int32
  alias SIZE_T = LibC::SizeT

  struct COORD
    x : Int16
    y : Int16
  end

  # STARTUPINFOEXW: STARTUPINFOW followed by attribute list pointer.
  # CreateProcessW is called with a pointer to the embedded STARTUPINFOW
  # and EXTENDED_STARTUPINFO_PRESENT so the OS reads the full EX layout.
  struct STARTUPINFOEXW
    startup_info : LibC::STARTUPINFOW
    lp_attribute_list : Void*
  end

  # ProcThreadAttributeValue(22, FALSE, TRUE, FALSE) == 0x00020016
  PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE = 0x00020016_u64
  EXTENDED_STARTUPINFO_PRESENT        = 0x00080000_u32

  fun CreatePipe(
    hReadPipe : HANDLE*,
    hWritePipe : HANDLE*,
    lpPipeAttributes : LibC::SECURITY_ATTRIBUTES*,
    nSize : DWORD,
  ) : BOOL

  fun CreatePseudoConsole(
    size : COORD,
    hInput : HANDLE,
    hOutput : HANDLE,
    dwFlags : DWORD,
    phPC : HANDLE*,
  ) : HRESULT

  fun ResizePseudoConsole(hPC : HANDLE, size : COORD) : HRESULT
  fun ClosePseudoConsole(hPC : HANDLE) : Void

  fun InitializeProcThreadAttributeList(
    lpAttributeList : Void*,
    dwAttributeCount : DWORD,
    dwFlags : DWORD,
    lpSize : SIZE_T*,
  ) : BOOL

  fun UpdateProcThreadAttribute(
    lpAttributeList : Void*,
    dwFlags : DWORD,
    attribute : UInt64,
    lpValue : Void*,
    cbSize : SIZE_T,
    lpPreviousValue : Void*,
    lpReturnSize : SIZE_T*,
  ) : BOOL

  fun DeleteProcThreadAttributeList(lpAttributeList : Void*) : Void
end

module ConPTYEcho
  extend self

  ROWS = 24_i16
  COLS = 80_i16

  def main : Int32
    input_read = Pointer(Void).null
    input_write = Pointer(Void).null
    output_read = Pointer(Void).null
    output_write = Pointer(Void).null
    hpc = Pointer(Void).null
    attr_list = Pointer(Void).null

    raise_last("CreatePipe input") unless LibConPTY.CreatePipe(pointerof(input_read), pointerof(input_write), nil, 0) != 0
    raise_last("CreatePipe output") unless LibConPTY.CreatePipe(pointerof(output_read), pointerof(output_write), nil, 0) != 0

    size = LibConPTY::COORD.new
    size.x = COLS
    size.y = ROWS

    hr = LibConPTY.CreatePseudoConsole(size, input_read, output_write, 0, pointerof(hpc))
    raise "CreatePseudoConsole failed: HRESULT 0x#{hr.to_u32.to_s(16)}" if hr != 0

    # Host no longer needs the ConPTY-side ends; close so child exit
    # breaks the pipes cleanly.
    LibC.CloseHandle(input_read)
    input_read = Pointer(Void).null
    LibC.CloseHandle(output_write)
    output_write = Pointer(Void).null

    attr_list = prepare_attribute_list(hpc)

    si = LibConPTY::STARTUPINFOEXW.new
    si.startup_info = LibC::STARTUPINFOW.new
    si.startup_info.cb = sizeof(LibConPTY::STARTUPINFOEXW).to_u32
    si.lp_attribute_list = attr_list

    # Mutable UTF-16 command line (CreateProcessW may write to it).
    # Slice from #to_utf16 is null-terminated past its logical content.
    cmd = "cmd.exe /c echo ok".to_utf16

    pi = LibC::PROCESS_INFORMATION.new
    ok = LibC.CreateProcessW(
      nil,
      cmd.to_unsafe,
      nil,
      nil,
      0, # bInheritHandles — ConPTY attachment is via the attribute list
      LibConPTY::EXTENDED_STARTUPINFO_PRESENT,
      nil,
      nil,
      pointerof(si).as(LibC::STARTUPINFOW*),
      pointerof(pi),
    )
    raise_last("CreateProcessW") if ok == 0

    screen = Term::VT::Screen.new(rows: ROWS.to_i, cols: COLS.to_i)

    # Avoid ReadFile-before-wait: ConPTY often keeps the output pipe open
    # until ClosePseudoConsole, so a blocking ReadFile can hang forever and
    # never reach WaitForSingleObject. For this tiny `echo ok` prototype the
    # OS pipe buffer holds the output; wait for exit, close ConPTY (EOF),
    # then drain. A real Session port needs a dedicated reader thread/fiber
    # with overlapped I/O for large interactive output (MS deadlock warning).
    if LibC.WaitForSingleObject(pi.hProcess, LibC::INFINITE) != LibC::WAIT_OBJECT_0
      raise_last("WaitForSingleObject(child)")
    end

    LibConPTY.ClosePseudoConsole(hpc)
    hpc = Pointer(Void).null

    drain_output(output_read, screen)
    puts screen.snapshot

    LibC.CloseHandle(pi.hThread)
    LibC.CloseHandle(pi.hProcess)
    LibConPTY.DeleteProcThreadAttributeList(attr_list)
    attr_list = Pointer(Void).null
    LibC.CloseHandle(input_write)
    LibC.CloseHandle(output_read)

    0
  ensure
    # Best-effort cleanup if we raised mid-setup.
    LibConPTY.ClosePseudoConsole(hpc) unless hpc.null?
    LibConPTY.DeleteProcThreadAttributeList(attr_list) unless attr_list.null?
  end

  private def prepare_attribute_list(hpc : Void*) : Void*
    bytes = LibC::SizeT.zero
    LibConPTY.InitializeProcThreadAttributeList(nil, 1, 0, pointerof(bytes))
    # First call is expected to fail and set bytesRequired.

    list = LibC.HeapAlloc(LibC.GetProcessHeap, 0, bytes)
    raise "HeapAlloc attribute list failed" if list.null?

    unless LibConPTY.InitializeProcThreadAttributeList(list, 1, 0, pointerof(bytes)) != 0
      LibC.HeapFree(LibC.GetProcessHeap, 0, list)
      raise_last("InitializeProcThreadAttributeList")
    end

    # UpdateProcThreadAttribute copies sizeof(HPCON) from *lpValue.
    hpc_local = hpc
    unless LibConPTY.UpdateProcThreadAttribute(
             list,
             0,
             LibConPTY::PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
             pointerof(hpc_local).as(Void*),
             sizeof(Void*).to_u64!,
             nil,
             nil,
           ) != 0
      LibConPTY.DeleteProcThreadAttributeList(list)
      LibC.HeapFree(LibC.GetProcessHeap, 0, list)
      raise_last("UpdateProcThreadAttribute(PSEUDOCONSOLE)")
    end

    list
  end

  # Blocking ReadFile loop; returns on pipe EOF (including after ClosePseudoConsole).
  private def drain_output(output_read : Void*, screen : Term::VT::Screen) : Nil
    buf = Bytes.new(4096)
    read = 0_u32

    loop do
      ok = LibC.ReadFile(output_read, buf.to_unsafe, buf.size.to_u32, pointerof(read), nil)
      break if ok == 0 || read == 0
      screen.feed(buf[0, read.to_i])
    end
  end

  private def raise_last(what : String) : NoReturn
    raise "#{what} failed (GetLastError=#{LibC.GetLastError})"
  end
end

exit ConPTYEcho.main
