# frozen_string_literal: true

if ENV['COVERAGE'] == '1'
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

ENV['SHOKO_TEST_MODE'] ||= '1'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'shoko'
require 'shoko/test_support/test_mode'
Shoko::TestSupport::TestMode.activate!

Dir[File.join(__dir__, 'support/**/*.rb')].each { |file| require file }

module SpecBookFixtures
  module_function

  REQUIRED_FILES = [
    'Persuasion (Jane Austen).mobi',
    'Pride Prejudice (Jane Austen).azw',
    'Emma (Jane Austen).azw3',
    'Pride And Prejudice (Austen Jane).rtf',
  ].freeze

  def enabled?
    ENV['SHOKO_BOOK_FIXTURES'] == '1'
  end

  def root
    raw = ENV['SHOKO_FIXTURES_DIR']
    return File.expand_path('..', __dir__) if raw.nil? || raw.strip.empty?

    File.expand_path(raw)
  end

  def path(filename)
    File.join(root, filename)
  end

  def missing_files
    REQUIRED_FILES.reject { |name| File.exist?(path(name)) }
  end
end

module SpecBookFixtureHelpers
  def book_fixture_path(filename)
    SpecBookFixtures.path(filename)
  end

  def book_fixtures_enabled?
    SpecBookFixtures.enabled?
  end
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include SpecEnvHelpers
  config.include SpecBookFixtureHelpers

  config.filter_run_excluding requires_book_fixtures: true unless SpecBookFixtures.enabled?

  config.before(:suite) do
    next unless SpecBookFixtures.enabled?

    missing = SpecBookFixtures.missing_files
    next if missing.empty?

    lines = missing.map { |name| "- #{name}" }
    abort <<~MSG
      Missing required book fixtures under #{SpecBookFixtures.root}
      #{lines.join("\n")}
    MSG
  end

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.order = :random
end
