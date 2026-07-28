# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Shoko::Adapters::Translation::EngineClient do
  around do |example|
    Dir.mktmpdir('shoko-engine-client') do |dir|
      @dir = dir
      example.run
    end
  end

  after { client.shutdown }

  # A stand-in engine speaking the real JSON-lines protocol.
  def write_fake_engine(body)
    path = File.join(@dir, 'fake-engine')
    File.write(path, <<~RUBY)
      #!#{RbConfig.ruby}
      require 'json'
      $stdout.sync = true
      #{body}
    RUBY
    File.chmod(0o755, path)
    path
  end

  def standard_engine
    write_fake_engine(<<~'RUBY')
      while (line = $stdin.gets)
        req = JSON.parse(line)
        case req['op']
        when 'load'
          puts({ ok: req['model'] != '/missing.bin' }.merge(
            req['model'] == '/missing.bin' ? { error: 'cannot open model file' } : {}
          ).to_json)
        when 'translate'
          exit!(1) if req['text'] == 'CRASH'
          puts({
            ok: true,
            text: "T[#{req['text']}]",
            finish_reason: req['text'] == 'CUT' ? 'max_tokens' : 'eos'
          }.to_json)
        else
          puts({ ok: false, error: 'unknown op' }.to_json)
        end
      end
    RUBY
  end

  subject(:client) { described_class.new(engine_path: engine_path) }

  let(:engine_path) { standard_engine }

  it 'loads a model and translates through it' do
    client.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
    expect(client.translate('eten', 'Tere!')).to eq('T[Tere!]')
  end

  it 'surfaces decoder truncation metadata' do
    client.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')

    response = client.translate_with_metadata('eten', 'CUT')

    expect(response.text).to eq('T[CUT]')
    expect(response).to be_truncated
  end

  it 'raises a typed error when the engine rejects a load' do
    expect do
      client.ensure_loaded('bad', model_path: '/missing.bin', vocab_path: '/v.spm')
    end.to raise_error(described_class::EngineError, /cannot open model file/)
  end

  it 'raises engine_missing when the binary does not exist' do
    absent = described_class.new(engine_path: File.join(@dir, 'nope'))
    expect do
      absent.ensure_loaded('x', model_path: '/m.bin', vocab_path: '/v.spm')
    end.to raise_error(described_class::EngineError) { |e| expect(e.code).to eq(:engine_missing) }
  end

  it 'raises when translating through a slot that was never loaded' do
    expect { client.translate('ghost', 'text') }.to raise_error(described_class::EngineError)
  end

  it 'reports a crash as engine_died and recovers on the next load' do
    client.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
    expect { client.translate('eten', 'CRASH') }
      .to raise_error(described_class::EngineError) { |e| expect(e.code).to eq(:engine_died) }

    client.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
    expect(client.translate('eten', 'again')).to eq('T[again]')
  end

  it 'rejects malformed success responses and retires that process' do
    malformed = described_class.new(
      engine_path: write_fake_engine("while $stdin.gets\n  puts({ ok: true }.to_json)\nend")
    )

    expect do
      malformed.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
      malformed.translate('eten', 'hello')
    end.to raise_error(described_class::EngineError) { |error|
      expect(error.code).to eq(:engine_protocol)
    }
    expect(malformed.running?).to be(false)
  ensure
    malformed&.shutdown
  end

  it 'times out and forcibly retires an unresponsive process' do
    stub_const("#{described_class}::READ_TIMEOUT_SECONDS", 0.05)
    stalled = described_class.new(
      engine_path: write_fake_engine("while $stdin.gets\n  sleep 60\nend")
    )

    expect do
      stalled.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
    end.to raise_error(described_class::EngineError) { |error|
      expect(error.code).to eq(:engine_timeout)
    }
    expect(stalled.running?).to be(false)
  ensure
    stalled&.shutdown
  end

  it 'forgets a slot reported as evicted by the engine' do
    evicting = described_class.new(
      engine_path: write_fake_engine(<<~'RUBY')
        loads = 0
        while (line = $stdin.gets)
          req = JSON.parse(line)
          if req['op'] == 'load'
            loads += 1
            response = { ok: true }
            response[:evicted] = 'first' if loads == 2
            puts(response.to_json)
          else
            puts({ ok: true, text: req['text'], finish_reason: 'eos' }.to_json)
          end
        end
      RUBY
    )
    evicting.ensure_loaded('first', model_path: '/a.bin', vocab_path: '/a.spm')
    evicting.ensure_loaded('second', model_path: '/b.bin', vocab_path: '/b.spm')

    expect { evicting.translate('first', 'hello') }
      .to raise_error(described_class::EngineError, /not loaded/)
  ensure
    evicting&.shutdown
  end

  it 'shuts the child process down cleanly' do
    client.ensure_loaded('eten', model_path: '/m.bin', vocab_path: '/v.spm')
    expect(client.running?).to be(true)
    client.shutdown
    expect(client.running?).to be(false)
  end
end
