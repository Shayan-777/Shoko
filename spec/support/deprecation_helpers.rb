# frozen_string_literal: true

module DeprecationHelpers
  def capture_warnings
    messages = []
    allow(Kernel).to receive(:warn) { |msg| messages << msg }
    yield
    messages
  end
end

RSpec.configure do |config|
  config.include DeprecationHelpers
end
