# frozen_string_literal: true

# Scaling benchmark for Document#root.each.
#
# Run after compiling:
#   bundle exec rake compile
#   bundle exec ruby benchmark/each_scaling.rb [max_n] [time_limit_seconds]
#
# For each shape, doubles N and times `each` plus the FFI calls it makes.
# The "x" column is time(N) / time(N/2): ~2 means linear, ~4 means quadratic.

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../ext", __dir__)
require "yerba"

MAX_N = Integer(ARGV[0] || 16_000)
TIME_LIMIT = Float(ARGV[1] || 5.0)
SIZES = [500].tap { |sizes| sizes << (sizes.last * 2) while sizes.last * 2 <= MAX_N }

SHAPES = {
  "seq of maps" => lambda do |n|
    (0...n).map { |i| "- name: item#{i}\n  value: #{i}\n  tags: [a, b]\n" }.join
  end,
  "seq of scalars" => lambda do |n|
    (0...n).map { |i| "- item#{i}\n" }.join
  end,
  "map of maps" => lambda do |n|
    (0...n).map { |i| "key#{i}:\n  name: item#{i}\n  value: #{i}\n" }.join
  end,
  "map of scalars" => lambda do |n|
    (0...n).map { |i| "key#{i}: item#{i}\n" }.join
  end,
}.freeze

def time
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
end

# Each probe isolates one piece of what `each` does, so the costs can be compared.
def probes(document)
  root = document.root

  common = {
    "root.each {}" => -> { root.each { |*| nil } },
    "each + field access" => lambda {
      root.each { |*args|
        item = args.last
        item["name"] if item.is_a?(Yerba::Map)
      }
    },
    "value_at('')" => -> { document.value_at("") },
  }

  specific = if root.is_a?(Yerba::Sequence)
               {
                 "get_all('[]')" => -> { document.get_all("[]") },
                 "value_at('[]')" => -> { document.value_at("[]") },
                 "length" => -> { root.length },
               }
             else
               {
                 "get_all('*')" => -> { document.get_all("*") },
                 "keys_at('')" => -> { document.keys_at("") },
               }
             end

  common.merge(specific)
end

def format_seconds(seconds)
  seconds < 1 ? format("%<ms>8.1fms", ms: seconds * 1000) : format("%<s>8.2fs ", s: seconds)
end

SHAPES.each do |shape, generate|
  puts "\n== #{shape} =="

  results = Hash.new { |hash, key| hash[key] = {} }
  skipped = {}

  SIZES.each do |n|
    document = Yerba.parse(generate.call(n))

    probes(document).each do |name, probe|
      next if skipped[name]

      elapsed = time(&probe)
      results[name][n] = elapsed
      skipped[name] = true if elapsed > TIME_LIMIT
    end
  end

  header = "probe".ljust(22) + SIZES.map { |n| "#{n.to_s.rjust(10)} #{"x".rjust(5)}" }.join
  puts header
  puts "-" * header.length

  results.each do |name, by_size|
    row = SIZES.map do |n|
      elapsed = by_size[n]
      next "#{"-".rjust(10)} #{"".rjust(5)}" unless elapsed

      previous = by_size[n / 2]
      ratio = previous&.positive? ? format("%<ratio>5.1f", ratio: elapsed / previous) : ""
      "#{format_seconds(elapsed)} #{ratio.rjust(5)}"
    end

    puts name.ljust(22) + row.join
  end
end

puts "\nx = time(N) / time(N/2). ~2 linear, ~4 quadratic. '-' = skipped after exceeding #{TIME_LIMIT}s."
