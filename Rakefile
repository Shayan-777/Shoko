# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'json'
require 'English'
require 'fileutils'
require 'shellwords'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:rubocop) do |task|
  # Enforced lint lane for debt burn-down scope.
  task.patterns = ['lib/shoko/**/*.rb']
end

namespace :rubocop do
  desc 'Run RuboCop on the full repository (non-blocking visibility lane)'
  task :all do
    sh 'bundle exec rubocop'
  end

  desc 'Generate strict RuboCop debt report for lib/shoko without .rubocop_todo.yml'
  task :strict_report do
    sh 'ruby script/quality/rubocop_lib_strict_report.rb'
  end
end

desc 'Run all quality checks'
task quality: %i[spec rubocop]

task default: :quality

namespace :test do
  module RSpecLane
    module_function

    RESULT_DIR = File.expand_path('tmp/rspec-results', __dir__)

    def run!(name:, args:, env: {})
      FileUtils.mkdir_p(RESULT_DIR)
      output_path = File.join(RESULT_DIR, "#{name}.json")
      FileUtils.rm_f(output_path)
      command = ['bundle', 'exec', 'rspec', *args, '--format', 'json', '--out', output_path]

      puts "==> #{name}: #{Shellwords.join(command)}"
      success = system(env, *command)
      pending = pending_count(output_path)

      raise "Pending examples detected in #{name}: #{pending}" if pending.positive?
      raise "RSpec failed in #{name} (exit #{$CHILD_STATUS.exitstatus})" unless success
    end

    def pending_count(path)
      return 0 unless File.exist?(path)

      payload = JSON.parse(File.read(path))
      payload.dig('summary', 'pending_count').to_i
    rescue JSON::ParserError => e
      raise "Unable to parse RSpec JSON report at #{path}: #{e.message}"
    end
  end

  desc 'Run architecture and wiring guardrail specs only'
  task :guardrails do
    FileUtils.mkdir_p(RSpecLane::RESULT_DIR)
    fallback_report_path = File.join(RSpecLane::RESULT_DIR, 'fallback-report.json')
    fallback_command = ['ruby', File.expand_path('script/architecture/fallback_report.rb', __dir__)]
    puts "==> fallback-report: #{Shellwords.join(fallback_command)}"
    fallback_payload = IO.popen(fallback_command, &:read)
    File.write(fallback_report_path, fallback_payload)
    raise 'Fallback report detected guardrail offenders' unless $CHILD_STATUS.success?

    guardrail_targets = [
      'spec/core/architecture',
      'spec/adapters/input/reader_input_controller_spec.rb',
      'spec/adapters/input/controllers/menu/input_controller_spec.rb',
      'spec/composition/dependencies/bundle_guardrails_spec.rb',
    ]

    RSpecLane.run!(
      name: 'guardrails',
      args: [*guardrail_targets, '--seed', '10101']
    )
  end

  desc 'Run required non-fixture specs across fixed deterministic seeds'
  task :required do
    %w[10101 20202 30303].each do |seed|
      RSpecLane.run!(
        name: "required-seed-#{seed}",
        args: ['--tag', '~requires_book_fixtures', '--seed', seed]
      )
    end
  end

  desc 'Run fixture-dependent specs only'
  task :fixtures do
    env = {
      'SHOKO_BOOK_FIXTURES' => '1',
    }
    env['SHOKO_FIXTURES_DIR'] = ENV['SHOKO_FIXTURES_DIR'] if ENV.key?('SHOKO_FIXTURES_DIR')

    RSpecLane.run!(
      name: 'fixtures',
      env: env,
      args: ['--tag', 'requires_book_fixtures', '--seed', '30303']
    )
  end

  desc 'Run tests with coverage'
  task :coverage do
    ENV['COVERAGE'] = '1'
    Rake::Task['spec'].invoke
  end
end

desc 'Console with library loaded'
task :console do
  require 'irb'
  require 'shoko'
  ARGV.clear
  IRB.start
end
