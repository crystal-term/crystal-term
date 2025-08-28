require "../src/term-progress"

# Demo: Progress bar with embedded spinner token

multi = Term::Progress::Multi.new("Processing jobs")

bar = multi.register(":spinner [:bar] :percent :current/:total", total: 100_i64)

100.times do |i|
  sleep 30.milliseconds
  bar.advance
end

bar.finish("done")
