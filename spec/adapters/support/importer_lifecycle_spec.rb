# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Support::ImporterLifecycle do
  let(:host_class) do
    Class.new do
      include Shoko::Adapters::Support::ImporterLifecycle

      def initialize(progress_reporter: nil, instrumentation: nil)
        @progress_reporter = progress_reporter
        @instrumentation = instrumentation
      end

      def call_report(message, progress: nil)
        report(message, progress: progress)
      end

      def call_instrument(label, &)
        instrument(label, &)
      end

      def call_fallback(path, strip_suffixes: [], trim_parenthetical: false, &)
        fallback_title_from_path(path, strip_suffixes: strip_suffixes, trim_parenthetical: trim_parenthetical, &)
      end
    end
  end

  it 'dispatches report updates to callable progress reporters' do
    events = []
    reporter = Class.new do
      def initialize(events)
        @events = events
      end

      def update_status(message: nil, progress: nil)
        @events << [message, progress]
      end
    end.new(events)
    host = host_class.new(progress_reporter: reporter)

    host.call_report('Loading...', progress: 0.5)

    expect(events).to eq([['Loading...', 0.5]])
  end

  it 'uses instrumentation when available and yields directly when missing' do
    measurements = []
    instrumentation = double('Instrumentation')
    allow(instrumentation).to receive(:measure) do |label, &block|
      measurements << label
      block.call
    end

    host = host_class.new(instrumentation: instrumentation)
    value = host.call_instrument('sample.step') { :ok }

    expect(value).to eq(:ok)
    expect(measurements).to eq(['sample.step'])

    host_without_instrumentation = host_class.new
    expect(host_without_instrumentation.call_instrument('plain.step') { :plain }).to eq(:plain)
  end

  it 'builds sanitized fallback titles with compound suffix and parenthetical trimming' do
    host = host_class.new

    fb2 = host.call_fallback('/tmp/My_Book.fb2.zip', strip_suffixes: ['.fb2.zip'])
    rtf = host.call_fallback('/tmp/Pride_And_Prejudice (Austen Jane).rtf', trim_parenthetical: true)

    expect(fb2).to eq('My Book')
    expect(rtf).to eq('Pride And Prejudice')
  end
end
