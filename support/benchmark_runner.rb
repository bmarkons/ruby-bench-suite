require 'benchmark/ips'
require 'json'

module Benchmark
  module Runner
    def self.run(label=nil, version:, time:, disable_gc:, warmup:, &block)
      unless block_given?
        raise ArgumentError.new, "You must pass block to run"
      end

      GC.disable if disable_gc

      ips_result = compute_ips(time, warmup, label, &block)
      objects_result = compute_objects(&block)

      print_output(ips_result, objects_result, label, version)
    end

    def self.compute_ips(time, warmup, label, &block)
      report = Benchmark.ips(time, warmup, true) do |x|
        x.report(label) { yield }
      end

      report.entries.first
    end

    def self.compute_objects(&block)
      if block_given?
        key =
          if RUBY_VERSION < '2.2'
            :total_allocated_object
          else
            :total_allocated_objects
          end

        before = GC.stat[key]
        yield
        after = GC.stat[key]
        after - before
      end
    end

    def self.print_output(ips_result, objects_result, label, version)
      output = {
        label: label,
        version: version,
        iterations_per_second: ips_result.ips,
        iterations_per_second_standard_deviation: ips_result.stddev_percentage,
        total_allocated_objects_per_iteration: objects_result
      }.to_json

      puts output
    end
  end
end
