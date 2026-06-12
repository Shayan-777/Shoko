# frozen_string_literal: true

require 'spec_helper'
require 'rbconfig'
require 'shoko/adapters/runtime/prepagination_batch_process_adapter'

RSpec.describe Shoko::Adapters::Runtime::PrepaginationBatchProcessAdapter do
  let(:logger) { instance_double('Logger', debug: nil) }

  # A stand-in child: any ruby script run as `ruby SCRIPT --prepaginate-batch WxH`.
  def adapter_for_child(script)
    file = Tempfile.create(['fake-batch-child', '.rb'])
    file.write(script)
    file.flush
    [described_class.new(logger: logger, shoko_bin: file.path, ruby_bin: RbConfig.ruby), file]
  end

  after { @child_file && File.unlink(@child_file.path) }

  it 'streams the child JSON events and reports a clean completion' do
    adapter, @child_file = adapter_for_child(<<~RUBY)
      abort('bad args') unless ARGV == ['--prepaginate-batch', '120x40']
      puts '{"event":"start","total":1,"paths":["/books/a.epub"]}'
      puts 'not json — must be ignored'
      puts '{"event":"report","done":1}'
    RUBY

    events = []
    status = adapter.run_batch(width: 120, height: 40, on_event: ->(event) { events << event })

    expect(status).to eq(:completed)
    expect(events).to eq(
      [
        { event: 'start', total: 1, paths: ['/books/a.epub'] },
        { event: 'report', done: 1 },
      ]
    )
  end

  it 'reports :failed when the child exits non-zero' do
    adapter, @child_file = adapter_for_child('exit 3')

    status = adapter.run_batch(width: 80, height: 24, on_event: ->(event) { event })

    expect(status).to eq(:failed)
  end

  it 'reports :failed when the child cannot be spawned' do
    adapter = described_class.new(logger: logger, shoko_bin: '/nonexistent/shoko', ruby_bin: '/nonexistent/ruby')

    status = adapter.run_batch(width: 80, height: 24, on_event: ->(event) { event })

    expect(status).to eq(:failed)
  end

  it 'reports :cancelled when the child is stopped mid-run' do
    adapter, @child_file = adapter_for_child(<<~RUBY)
      $stdout.sync = true
      puts '{"event":"start","total":9,"paths":[]}'
      sleep 30
    RUBY

    status = nil
    runner = Thread.new do
      status = adapter.run_batch(
        width: 80, height: 24,
        on_event: ->(event) { @started = true if event[:event] == 'start' }
      )
    end
    sleep(0.05) until @started
    adapter.cancel_batch
    runner.join(5.0)

    expect(status).to eq(:cancelled)
  end

  it 'is safe to cancel when nothing is running' do
    adapter = described_class.new(logger: logger)

    expect { adapter.cancel_batch }.not_to raise_error
  end
end
