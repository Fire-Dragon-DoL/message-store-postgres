require_relative 'benchmark_init'

defaults = Test::Benchmark::Defaults.build

list = Controls::MessageData::Write::List.get(instances: defaults.total_cycles)

put = Put.build

result = Diagnostics::Sample.(defaults.cycles, warmup_cycles: defaults.warmup_cycles, gc: defaults.gc) do |i|
  entry = list[i]
  stream_name = defaults.stream_name || entry.stream_name
  put.(entry.message_data, stream_name)
end

puts
filename = Benchmark::RecordResult.('Put Benchmark', result)
puts
puts filename
puts
