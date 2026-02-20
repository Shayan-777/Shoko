# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      with_env('XDG_CONFIG_HOME' => dir) { example.run }
    end
  end

  describe 'option parsing' do
    it 'parses empty arguments' do
      # Use send to access private method for testing
      options, args = described_class.send(:parse_options, [])
      expect(options).to include(debug: false)
      expect(args).to be_empty
    end

    it 'parses -d flag' do
      options, _args = described_class.send(:parse_options, ['-d'])
      expect(options[:debug]).to be true
    end

    it 'parses --debug flag' do
      options, _args = described_class.send(:parse_options, ['--debug'])
      expect(options[:debug]).to be true
    end

    it 'parses --log PATH' do
      options, _args = described_class.send(:parse_options, ['--log', '/tmp/test.log'])
      expect(options[:log_path]).to eq('/tmp/test.log')
    end

    it 'parses --log-level LEVEL' do
      options, _args = described_class.send(:parse_options, ['--log-level', 'debug'])
      expect(options[:log_level]).to eq('debug')
    end

    it 'parses --profile PATH' do
      options, _args = described_class.send(:parse_options, ['--profile', '/tmp/profile.txt'])
      expect(options[:profile_path]).to eq('/tmp/profile.txt')
    end

    it 'leaves file argument in args' do
      _options, args = described_class.send(:parse_options, ['test.epub'])
      expect(args).to eq(['test.epub'])
    end

    it 'parses combined options and file' do
      options, args = described_class.send(:parse_options, ['-d', '--log', '/tmp/log', 'book.epub'])
      expect(options[:debug]).to be true
      expect(options[:log_path]).to eq('/tmp/log')
      expect(args).to eq(['book.epub'])
    end
  end

  describe '.debug_enabled?' do
    it 'returns true when options[:debug] is true' do
      result = described_class.send(:debug_enabled?, { debug: true })
      expect(result).to be true
    end

    it 'returns false when options[:debug] is false and DEBUG not set' do
      with_env('DEBUG' => nil) do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be false
      end
    end

    it 'returns true when DEBUG env is set to 1' do
      with_env('DEBUG' => '1') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be true
      end
    end

    it 'returns true when DEBUG env is set to true' do
      with_env('DEBUG' => 'true') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be true
      end
    end

    it 'returns false when DEBUG env is 0' do
      with_env('DEBUG' => '0') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be false
      end
    end

    it 'returns false when DEBUG env is false' do
      with_env('DEBUG' => 'false') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be false
      end
    end

    it 'returns false when DEBUG env is no' do
      with_env('DEBUG' => 'no') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be false
      end
    end

    it 'returns false when DEBUG env is off' do
      with_env('DEBUG' => 'off') do
        result = described_class.send(:debug_enabled?, { debug: false })
        expect(result).to be false
      end
    end
  end

  describe '.logger_level' do
    it 'returns :debug when debug is enabled' do
      with_env('DEBUG' => '1') do
        result = described_class.send(:logger_level, { debug: true })
        expect(result).to eq(:debug)
      end
    end

    it 'returns configured level when specified' do
      result = described_class.send(:logger_level, { debug: false, log_level: 'warn' })
      expect(result).to eq(:warn)
    end

    it 'returns :error as default' do
      with_env('DEBUG' => nil, 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: false, log_level: nil })
        expect(result).to eq(:error)
      end
    end

    it 'normalizes log level strings' do
      result = described_class.send(:normalize_log_level, 'INFO')
      expect(result).to eq(:info)
    end

    it 'returns nil for invalid log level' do
      result = described_class.send(:normalize_log_level, 'invalid')
      expect(result).to be_nil
    end
  end

  describe '.run' do
    let(:preflight_checker) { instance_double('PreflightChecker', call: nil) }
    let(:app_factory) { instance_double('AppFactory') }
    let(:application) { instance_double('UnifiedApplication', run: nil) }
    let(:migration_error_class) { Class.new(StandardError) }

    it 'runs preflight then builds and runs the application via injected hooks' do
      expect(preflight_checker).to receive(:call).ordered
      expect(app_factory).to receive(:call).with(
        epub_path: 'book.epub',
        log_config: hash_including(:level, :output, :profile_path, :debug)
      ).ordered.and_return(application)
      expect(application).to receive(:run).ordered

      described_class.run(
        ['book.epub'],
        preflight_checker: preflight_checker,
        app_factory: app_factory,
        migration_error_class: migration_error_class
      )
    end

    it 'prints migration errors and exits with code 1' do
      error = migration_error_class.new('run migrations')
      allow(preflight_checker).to receive(:call).and_raise(error)
      expect(described_class).to receive(:warn).with('run migrations')
      expect(described_class).to receive(:exit).with(1)

      described_class.run(
        [],
        preflight_checker: preflight_checker,
        app_factory: app_factory,
        migration_error_class: migration_error_class
      )
    end
  end
end
