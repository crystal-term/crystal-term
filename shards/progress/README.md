# Term::Progress

![spec status](https://github.com/crystal-term/progress/workflows/specs/badge.svg)

> Terminal progress bars and indicators for Crystal.

**Term::Progress** provides single progress bars, coordinated multi-bar displays,
transfer meters, formatter tokens, and spinner integration for terminal tasks.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     term-progress:
       github: crystal-term/progress
       version: ~> 1.0.0
   ```

2. Run `shards install`

## Usage

First require the library:

```crystal
require "term-progress"

bar = Term::Progress::Bar.new(total: 100_i64)

100.times do
  bar.advance
end

bar.finish("Complete!")
```

Use `format` to choose what the bar renders. Built-in tokens include `:bar`,
`:blocks`, `:dots`, `:percent`, `:current`, `:total`, `:fraction`, `:elapsed`,
`:eta`, `:rate`, `:mean_rate`, `:byte_rate`, and `:mean_byte_rate`.

```crystal
require "term-progress"

bar = Term::Progress::Bar.new(
  total: 1024_i64,
  format: "Downloading [:bar] :percent :byte_rate ETA: :eta"
)

bar.update(256_i64)
bar.finish("Downloaded!")
```

Custom tokens can be added with `update_tokens` and referenced from the format
string.

```crystal
require "term-progress"

bar = Term::Progress::Bar.new(
  total: 50_i64,
  format: ":title [:bar] :current/:total (:percent)"
)

bar.update_tokens(title: "Processing files")
bar.advance(25_i64)
bar.finish("Done!")
```

## Multiple Bars

`Term::Progress::Multi` manages several bars as one display.

```crystal
require "term-progress"

multi = Term::Progress::Multi.new("Overall Progress [:bar] :percent")

download_bar = multi.register("Download [:bar] :byte_rate", total: 500_i64)
install_bar = multi.register("Install  [:bar] :percent", total: 100_i64)

download_bar.advance(250_i64)
install_bar.advance(50_i64)

multi.finish_all("All tasks completed!")
```

## Meter

`Term::Progress::Meter` tracks rates, mean rates, elapsed time, and ETA values.
Bars expose their meter through `#meter`.

```crystal
require "term-progress"

meter = Term::Progress::Meter.new

meter.update(1024_i64)
sleep(10.milliseconds)
meter.update(4096_i64)

puts meter.format_rate(meter.mean_rate)
puts meter.format_time(meter.elapsed_time.total_seconds)
```

## Spinner Integration

Include the `:spinner` token in a bar format to animate it with
`term-spinner` frames.

```crystal
require "term-progress"

bar = Term::Progress::Bar.new(
  total: 100_i64,
  format: ":spinner [:bar] :percent :current/:total",
  spinner_format: :dots
)

bar.advance(10_i64)
bar.finish("done")
```

## Configuration

These options can be supplied to `Term::Progress::Bar.new`:

- `total`: total units of work, default `100`
- `format`: display template, default `"[:bar] :percent :current/:total"`
- `width`: rendered bar width, default based on terminal width
- `complete_char`, `incomplete_char`, `head_char`: progress bar characters
- `output`: destination IO, default `STDERR`
- `spinner_format`, `spinner_frames`, `spinner_interval`: spinner token options

Built-in format templates are available in
`Term::Progress::Formatters::FORMATS`: `default`, `minimal`, `download`,
`tasks`, `classic`, and `detailed`.

## Examples

Runnable examples live in `examples/`:

- `basic.cr` for single progress bars
- `custom_tokens.cr` for dynamic token updates
- `formatters.cr` for built-in formats and character sets
- `multi_bars.cr` and `multi_tree.cr` for coordinated bars
- `rates_and_timing.cr` for meter output
- `spinner_integration.cr` and `single_with_spinner.cr` for spinner tokens
