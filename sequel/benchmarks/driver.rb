#
# Sequel Benchmark driver
#
require 'bundler/setup'
require 'net/http'
require 'json'
require 'pathname'
require 'optparse'
require 'active_model'
require 'digest'

RAW_URL = 'https://raw.githubusercontent.com/ruby-bench/ruby-bench-suite/master/sequel/benchmarks/'

POSTGRES_TCP_ADDR = ENV['POSTGRES_PORT_5432_TCP_ADDR'] || 'localhost'
POSTGRES_PORT = ENV['POSTGRES_PORT_5432_TCP_PORT'] || 5432

MYSQL_TCP_ADDR = ENV['MYSQL_PORT_3306_TCP_ADDR'] || 'localhost'
MYSQL_PORT = ENV['MYSQL_PORT_3306_TCP_PORT'] || 3306

PSQL_URL  = "postgres://postgres@#{POSTGRES_TCP_ADDR}:#{POSTGRES_PORT}/rubybench"
MYSQL_URL = "mysql2://root@#{MYSQL_TCP_ADDR}:#{MYSQL_PORT}/rubybench"

class BenchmarkDriver
  def self.benchmark(options)
    self.new(options).run
  end

  def initialize(options)
    @repeat_count = options[:repeat_count]
    @pattern = options[:pattern]
  end

  def run
    benchmark_files.each do |file|
      next unless match_pattern?(file)

      run_benchmark(file, database: :psql, connection: PSQL_URL)
      run_benchmark(file, database: :mysql, connection: MYSQL_URL)
    end
  end

  private

  def benchmark_files
    Dir["#{File.expand_path(File.dirname(__FILE__))}/*"].select! { |path| path =~ /bm_.+/ }
  end

  def match_pattern?(path)
    @pattern.empty? || /#{@pattern.join('|')}/ =~ File.basename(path)
  end

  def run_benchmark(file, database:, connection:)
    with_prepared_statements    = execute command with_prepared_statements: true
    without_prepared_statements = execute command with_prepared_statements: false

    return if with_prepared_statements.nil? || without_prepared_statements.nil?

    script_url = "#{RAW_URL}#{Pathname.new(file).basename}"
    digest = generate_digest(file, database)

    puts "Posting results to Web UI...."

    # TODO
  end

  def measure_sequel(script, connection, path, database)
    connection_string = Proc.new do |prepared_statements|
      "DATABASE_URL=#{connection}?prepared_statements=#{prepared_statements} #{script}"
    end

    with_prepared_statements = measure(connection_string.call(true))
    return unless with_prepared_statements
    without_prepared_statements = measure(connection_string.call(false))
    return unless without_prepared_statements

    form_data = default_form_data(with_prepared_statements, path, database)

    submit_request(form_data, {
      "benchmark_run[result][with_prepared_statements]" => with_prepared_statements["iterations_per_second"].round(3),
      "benchmark_run[result][without_prepared_statements]" => without_prepared_statements["iterations_per_second"].round(3),
      'benchmark_result_type[name]' => 'Number of iterations per second',
      'benchmark_result_type[unit]' => 'Iterations per second'
    })

    submit_request(form_data, {
      "benchmark_run[result][with_prepared_statements]" => with_prepared_statements["total_allocated_objects_per_iteration"],
      "benchmark_run[result][without_prepared_statements]" => without_prepared_statements["total_allocated_objects_per_iteration"],
      'benchmark_result_type[name]' => 'Allocated objects',
      'benchmark_result_type[unit]' => 'Objects'
    })
  end

  def generate_request
    request = Net::HTTP::Post.new('/benchmark_runs')
    request.basic_auth(ENV["API_NAME"], ENV["API_PASSWORD"])
    request
  end

  def default_form_data(output, path, database)
    data = {
    }

    if(ENV['SEQUEL_COMMIT_HASH'])
      data['commit_hash'] = ENV['SEQUEL_COMMIT_HASH']
    elsif(ENV['SEQUEL_VERSION'])
      data['version'] = ENV['SEQUEL_VERSION']
    end
    data
  end

  def submit_request(form_data, )
    request = generate_request
    request.set_form_data(form_data)
    endpoint.request(request)
  end

  def endpoint
    http = Net::HTTP.new(ENV["API_URL"] || 'rubybench.org', 443)
    http.use_ssl = true
    http
  end

  def generate_digest(path, database)
    string = "#{File.read(path)}#{`ruby -v`}#{ActiveModel.version}"

    case database
    when 'psql'
      string = "#{string}#{ENV['POSTGRES_ENV_PG_VERSION']}"
    when 'mysql'
      string = "#{string}#{ENV['MYSQL_ENV_MYSQL_VERSION']}"
    end

    Digest::SHA2.hexdigest(string)
  end

  def measure(script)
    begin
      results = []

      @repeat_count.times do
        result = JSON.parse(`#{script}`)

        puts "#{result["label"]} #{result["iterations_per_second"]}/ips"
        puts "#{result["label"]} #{result["total_allocated_objects_per_iteration"]} objects"

        results << result
      end

      results.sort_by do |result|
        result['iterations_per_second']
      end.last
    rescue JSON::ParserError
      # Do nothing
    end
  end
end

options = {
  repeat_count: 1,
  pattern: []
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby driver.rb [options]"

  opts.on("-r", "--repeat-count [NUM]", "Run benchmarks [NUM] times taking the best result") do |value|
    options[:repeat_count] = value.to_i
  end

  opts.on("-p", "--pattern <PATTERN1,PATTERN2,PATTERN3>", "Benchmark name pattern") do |value|
    options[:pattern] = value.split(',')
  end
end.parse!(ARGV)

BenchmarkDriver.benchmark(options)
