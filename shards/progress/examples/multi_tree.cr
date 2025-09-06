require "../src/term-progress"

# Demonstrates Multi wrappers (tree-like), mixed bar templates,
# and dynamic add/remove of bars.

multi = Term::Progress::Multi.new("Processing jobs")

bars = [] of Term::Progress::Bar

# 1) Spinner + classic bar
bars << multi.register(":spinner [:bar] :percent :current/:total", total: 120_i64)

# 2) Arrow-style bar with head character, no spinner
bars << multi.register("[:bar] :percent (:elapsed)", total: 80_i64)
bars[1].update_tokens(title: "Compile")

# 3) Smooth blocks with percent, no spinner
bars << multi.register(":blocks :percent", total: 60_i64)

150.times do |t|
  sleep 40.milliseconds

  # Advance each bar at different rates
  bars.each_with_index do |b, i|
    next if b.finished? || b.stopped?
    case i
    when 0
      # Slow and steady
      b.advance(1)
    when 1
      # Medium pace
      b.advance(2)
    else
      # Faster
      b.advance(3)
    end
  end

  # Dynamically add a new bar (no spinner, dot meter)
  if t == 50
    bars << multi.register(":dots :fraction", total: 70_i64)
  end

  # Dynamically remove a bar (e.g., remove the second if present)
  if t == 100 && bars.size > 2
    removed = bars.delete_at(1)
    multi.remove(removed)
  end
end
