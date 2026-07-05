require "../src/term"

color = Term::Color.new("#336699")
raise "term-color did not load" unless color.hex_string(prefix: true) == "#336699"

raise "term-cursor did not load" unless Term::Cursor.hide == "\e[?25l"
raise "term-screen did not load" unless Term::Screen.size.is_a?(Tuple(Int32, Int32))
raise "term-terminfo did not load" unless Term::Terminfo::Sequences.clear_screen == "\e[2J"

reader = Term::Reader.new(input: IO::Memory.new("x"), output: IO::Memory.new)
reader.on_key(:ctrl_c) { |_char, _event| }

prompt = Term::Prompt.new
raise "term-prompt did not load" unless prompt.reader.is_a?(Term::Reader)

spinner = Term::Spinner.new("loading", output: STDERR)
raise "term-spinner did not load" unless spinner.stopped?
