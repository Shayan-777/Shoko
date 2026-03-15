# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Shoko::Adapters::Monitoring::LoggerAdapter do
  it 'writes JSON log lines to output' do
    output = StringIO.new
    logger = described_class.new(level: :debug, output: output)

    logger.info('hello', tag: 'x')

    output.rewind
    line = output.read
    expect(line).to include('"message":"hello"')
    expect(line).to include('"severity":"INFO"')
  end

  it 'raises storage error when output write fails' do
    failing_output = instance_double('Output')
    allow(failing_output).to receive(:puts).and_raise(IOError, 'stream closed')

    logger = described_class.new(level: :debug, output: failing_output)

    expect { logger.error('boom') }.to raise_error(Shoko::StorageError, /log_write/)
  end

  it 'accepts a String output path and appends JSON log lines' do
    Dir.mktmpdir('logger-adapter-spec') do |dir|
      path = File.join(dir, 'app.log')
      logger = described_class.new(level: :debug, output: path)

      logger.info('hello-path')

      content = File.read(path)
      expect(content).to include('"message":"hello-path"')
      expect(content).to include('"severity":"INFO"')
    end
  end

  it 'accepts IO::NULL path without raising' do
    logger = described_class.new(level: :debug, output: IO::NULL)

    expect { logger.info('discarded') }.not_to raise_error
  end

  it 'normalizes string log levels' do
    output = StringIO.new
    logger = described_class.new(level: 'debug', output: output)

    expect { logger.debug('string-level') }.not_to raise_error
  end
end
