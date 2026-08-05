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

  it 'never lets an output write failure escape the diagnostic call' do
    failing_output = instance_double(IO)
    allow(failing_output).to receive(:puts).and_raise(IOError, 'stream closed')

    logger = described_class.new(level: :debug, output: failing_output)

    expect { logger.error('boom') }.not_to raise_error
  end

  it 'never lets string normalization failure escape the diagnostic call' do
    invalid_message = Object.new
    def invalid_message.to_s = raise 'bad to_s'

    logger = described_class.new(level: :debug, output: StringIO.new)

    expect { logger.info(invalid_message) }.not_to raise_error
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
