# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::WrappingService do
  let(:text_metrics) { Shoko::Core::Services::DefaultTextMetrics.new }
  let(:async_executor) { Shoko::Core::Services::InlineExecutor.new }
  let(:dependencies) do
    deps = Object.new
    tm = text_metrics
    ae = async_executor
    deps.define_singleton_method(:registered?) do |name|
      %i[text_metrics async_executor].include?(name)
    end
    deps.define_singleton_method(:resolve) do |name|
      case name
      when :text_metrics then tm
      when :async_executor then ae
      end
    end
    deps
  end

  it 'does not reuse window cache across different line sets' do
    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor,
      dependencies: dependencies
    )

    lines_a = ['alpha beta']
    lines_b = ['gamma']

    wrapped_a = service.wrap_window(lines_a, 0, 5, 0, 2)
    wrapped_b = service.wrap_window(lines_b, 0, 5, 0, 2)

    expect(wrapped_a).not_to eq(wrapped_b)
    expect(wrapped_b).to eq(['gamma'])
  end

  it 'reuses cached windows for identical line sets' do
    service = described_class.new(
      text_metrics: text_metrics,
      async_executor: async_executor,
      dependencies: dependencies
    )

    lines = ['alpha beta']
    first = service.wrap_window(lines, 0, 5, 0, 2)
    second = service.wrap_window(lines, 0, 5, 0, 2)

    expect(second).to eq(first)
  end
end
