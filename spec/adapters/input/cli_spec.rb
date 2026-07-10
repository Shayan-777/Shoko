# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::CLI do
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

    it 'prints version for -v and exits with status 0' do
      status = nil
      expect do
        begin
          described_class.send(:parse_options, ['-v'])
        rescue SystemExit => e
          status = e.status
        end
      end.to output(/#{Regexp.escape(Shoko::VERSION)}/).to_stdout
      expect(status).to eq(0)
    end

    it 'prints version for --version and exits with status 0' do
      status = nil
      expect do
        begin
          described_class.send(:parse_options, ['--version'])
        rescue SystemExit => e
          status = e.status
        end
      end.to output(/#{Regexp.escape(Shoko::VERSION)}/).to_stdout
      expect(status).to eq(0)
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
      with_env('DEBUG' => nil, 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: false, log_level: 'warn' })
        expect(result).to eq(:warn)
      end
    end

    it 'returns :error as default' do
      with_env('DEBUG' => nil, 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: false, log_level: nil })
        expect(result).to eq(:error)
      end
    end

    it 'keeps DEBUG env precedence over explicit --log-level when DEBUG is truthy' do
      with_env('DEBUG' => '1', 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: false, log_level: 'warn' })
        expect(result).to eq(:debug)
      end
    end

    it 'keeps --debug option precedence over explicit --log-level when DEBUG env is falsey' do
      with_env('DEBUG' => '0', 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: true, log_level: 'error' })
        expect(result).to eq(:debug)
      end
    end

    it 'uses explicit --log-level when DEBUG env is falsey and --debug is off' do
      with_env('DEBUG' => 'false', 'SHOKO_LOG_LEVEL' => nil) do
        result = described_class.send(:logger_level, { debug: false, log_level: 'info' })
        expect(result).to eq(:info)
      end
    end

    it 'uses SHOKO_LOG_LEVEL when no option is set and DEBUG env is falsey' do
      with_env('DEBUG' => 'off', 'SHOKO_LOG_LEVEL' => 'warn') do
        result = described_class.send(:logger_level, { debug: false, log_level: nil })
        expect(result).to eq(:warn)
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
    let(:app_factory) { instance_double('AppFactory') }
    let(:application) { instance_double('UnifiedApplication', run: nil) }
    let(:process_control) { instance_double('ProcessControl', terminate: nil) }

    it 'builds and runs the application via injected hooks' do
      expect(app_factory).to receive(:call).with(
        epub_path: 'book.epub',
        log_config: hash_including(:level, :output, :profile_path, :debug)
      ).ordered.and_return(application)
      expect(application).to receive(:run).ordered

      described_class.run(
        ['book.epub'],
        app_factory: app_factory,
        process_control: process_control
      )
    end

    it 'converts unexpected errors into a clean message and exit code 1' do
      allow(app_factory).to receive(:call).and_raise(StandardError, 'boom')
      output = StringIO.new

      described_class.run([], app_factory: app_factory, process_control: process_control, output: output)

      expect(output.string).to include('Error: boom (StandardError)')
      expect(output.string).to include('--log PATH')
      expect(process_control).to have_received(:terminate).with(1)
    end

    describe 'the --prepaginate-batch child entry' do
      let(:prepaginate_factory) { instance_double('PrepaginateFactory') }
      let(:batch) { instance_double('LibraryPrepaginationBatch') }

      before do
        allow(described_class).to receive(:deprioritize_current_process)
        allow(prepaginate_factory).to receive(:call).and_return(batch)
      end

      def run_batch_cli
        described_class.run(
          ['--prepaginate-batch', '120x40'],
          app_factory: app_factory,
          process_control: process_control,
          prepaginate_factory: prepaginate_factory
        )
      end

      it 'runs the batch at the parsed size and exits cleanly on completion' do
        allow(batch).to receive(:run).with(width: 120, height: 40).and_return(:completed)

        run_batch_cli

        expect(process_control).not_to have_received(:terminate)
      end

      it 'exits non-zero when the batch failed, so the parent never records it as done' do
        # The parent menu warmup only sees this process's exit status; a zero
        # exit for a failed batch would persist the size signature and
        # suppress every retry at that terminal size.
        allow(batch).to receive(:run).with(width: 120, height: 40).and_return(:failed)

        run_batch_cli

        expect(process_control).to have_received(:terminate).with(1)
      end
    end
  end

  describe '.logger_output' do
    it 'warns and falls back to IO::NULL when explicit --log path cannot be opened' do
      with_env('DEBUG' => nil) do
        allow(described_class).to receive(:ensure_log_directory)
        allow(File).to receive(:open).and_raise(Errno::EACCES, 'permission denied')
        expect(Kernel).to receive(:warn).with(include("Failed to open log path '/tmp/explicit.log'"))

        output, file = described_class.send(:logger_output, { debug: false, log_path: '/tmp/explicit.log' })

        expect(output).to eq(IO::NULL)
        expect(file).to be_nil
      end
    end

    it 'does not warn when no explicit log path is provided and output is null' do
      with_env('DEBUG' => nil, 'SHOKO_LOG_PATH' => nil) do
        expect(Kernel).not_to receive(:warn)

        output, file = described_class.send(:logger_output, { debug: false, log_path: nil })

        expect(output).to eq(IO::NULL)
        expect(file).to be_nil
      end
    end

    it 'does not warn for env-driven log path failures without explicit --log option' do
      with_env('DEBUG' => nil, 'SHOKO_LOG_PATH' => '/tmp/env-driven.log') do
        allow(described_class).to receive(:ensure_log_directory)
        allow(File).to receive(:open).and_raise(Errno::EACCES, 'permission denied')
        expect(Kernel).not_to receive(:warn)

        output, file = described_class.send(:logger_output, { debug: false, log_path: nil })

        expect(output).to eq(IO::NULL)
        expect(file).to be_nil
      end
    end
  end
end
