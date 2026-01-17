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

Dir[File.join(__dir__, 'support/**/*.rb')].each { |file| require file }

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.include SpecEnvHelpers
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.order = :random
end
