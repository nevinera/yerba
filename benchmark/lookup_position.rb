# frozen_string_literal: true

# Times a single field read by the position of the item it reads from.
#
# Run after compiling:
#   bundle exec rake compile
#   bundle exec ruby benchmark/lookup_position.rb [n]
#
# If a read gets slower the later its item appears, each lookup is scanning
# the collection, and reading a field from every item is quadratic.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext", __dir__)
require "yerba"

N = Integer(ARGV[0] || 8000)
REPETITIONS = 200

map_document = Yerba.parse((0...N).map { |i| "key#{i}:\n  name: item#{i}\n  value: #{i}\n" }.join)
sequence_document = Yerba.parse((0...N).map { |i| "- name: item#{i}\n  value: #{i}\n" }.join)

def microseconds(&)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  REPETITIONS.times(&)
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) / REPETITIONS * 1_000_000
end

puts "index".ljust(8) + ["map[]", "map value_at", "sequence[]", "sequence value_at"].map { |label| " #{label.rjust(18)}" }.join

[0, N / 2, N - 1].each do |index|
  timings = [
    microseconds { map_document["key#{index}.name"] },
    microseconds { map_document.value_at("key#{index}.name") },
    microseconds { sequence_document["[#{index}].name"] },
    microseconds { sequence_document.value_at("[#{index}].name") }
  ]

  puts index.to_s.ljust(8) + timings.map { |timing| format(" %<us>16.1fus", us: timing) }.join
end
