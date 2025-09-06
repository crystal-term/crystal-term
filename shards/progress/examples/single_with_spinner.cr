require "../src/term-progress"

# Minimal example: a single progress bar with an embedded spinner

bar = Term::Progress::Bar.new(
  total: 80_i64,
  format: ":spinner [:bar] :percent :current/:total"
)

80.times do
  sleep 30.milliseconds
  bar.advance
end

bar.finish("done")
