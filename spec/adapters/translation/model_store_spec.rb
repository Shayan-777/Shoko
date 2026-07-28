# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Shoko::Adapters::Translation::ModelStore do
  around do |example|
    Dir.mktmpdir('shoko-model-store') do |dir|
      @root = dir
      example.run
    end
  end

  subject(:store) { described_class.new(root: @root) }

  def install_pack(from, to, version: '1.0')
    dir = store.create_pack_dir(from, to)
    File.write(File.join(dir, 'model.bin'), 'model-bytes')
    File.write(File.join(dir, 'vocab.spm'), 'vocab-bytes')
    store.write_manifest(from, to, version: version, model_file: 'model.bin', vocab_file: 'vocab.spm')
  end

  it 'reports nothing installed for a missing root' do
    expect(described_class.new(root: File.join(@root, 'absent')).installed_packs).to eq([])
  end

  it 'lists installed packs with resolved file paths' do
    install_pack('et', 'en')
    packs = store.installed_packs
    expect(packs.length).to eq(1)
    pack = packs.first
    expect(pack.from).to eq('et')
    expect(pack.to).to eq('en')
    expect(pack.version).to eq('1.0')
    expect(File.file?(pack.model_path)).to be(true)
    expect(File.file?(pack.vocab_path)).to be(true)
  end

  it 'answers installed? and find per pair' do
    install_pack('et', 'en')
    expect(store.installed?('et', 'en')).to be(true)
    expect(store.installed?('en', 'et')).to be(false)
    expect(store.find('et', 'en')).not_to be_nil
    expect(store.find('en', 'et')).to be_nil
  end

  it 'ignores a pack whose files are missing' do
    dir = store.create_pack_dir('de', 'en')
    File.write(File.join(dir, described_class::MANIFEST_NAME),
               JSON.generate(from: 'de', to: 'en', version: '1.0', model: 'model.bin', vocab: 'vocab.spm'))
    expect(store.installed?('de', 'en')).to be(false)
  end

  it 'ignores a pack with a corrupt manifest' do
    dir = store.create_pack_dir('fr', 'en')
    File.write(File.join(dir, described_class::MANIFEST_NAME), '{not json')
    expect(store.installed_packs).to eq([])
  end

  it 'removes an installed pack directory' do
    install_pack('et', 'en')
    store.remove('et', 'en')
    expect(store.installed?('et', 'en')).to be(false)
    expect(Dir.exist?(store.pack_dir('et', 'en'))).to be(false)
  end

  it 'keeps the previous complete pack when a staged update fails' do
    store.install('et', 'en', version: '1.0', model_file: 'model.bin', vocab_file: 'vocab.spm') do |dir|
      File.write(File.join(dir, 'model.bin'), 'old-model')
      File.write(File.join(dir, 'vocab.spm'), 'old-vocab')
    end

    expect do
      store.install('et', 'en', version: '2.0', model_file: 'model.bin', vocab_file: 'vocab.spm') do |dir|
        File.write(File.join(dir, 'model.bin'), 'partial-new-model')
        raise 'download interrupted'
      end
    end.to raise_error(RuntimeError, /interrupted/)

    pack = store.find('et', 'en')
    expect(pack.version).to eq('1.0')
    expect(File.read(pack.model_path)).to eq('old-model')
  end

  it 'notifies the engine lifecycle only after committed changes' do
    changes = []
    notifying = described_class.new(root: @root, on_change: ->(from, to) { changes << [from, to] })
    notifying.install('EN', 'DE', version: '1.0', model_file: 'model.bin', vocab_file: 'vocab.spm') do |dir|
      File.write(File.join(dir, 'model.bin'), 'model')
      File.write(File.join(dir, 'vocab.spm'), 'vocab')
    end
    notifying.remove('en', 'de')

    expect(changes).to eq([%w[en de], %w[en de]])
  end

  it 'rejects manifest identity mismatches for a requested pair' do
    dir = store.create_pack_dir('et', 'en')
    File.write(File.join(dir, 'model.bin'), 'model')
    File.write(File.join(dir, 'vocab.spm'), 'vocab')
    File.write(
      File.join(dir, described_class::MANIFEST_NAME),
      JSON.generate(from: 'de', to: 'en', version: '1.0', model: 'model.bin', vocab: 'vocab.spm')
    )

    expect(store.find('et', 'en')).to be_nil
  end

  it 'rejects nested or colliding pack file names' do
    expect do
      store.write_manifest('et', 'en', version: '1', model_file: '../model.bin', vocab_file: 'vocab.spm')
    end.to raise_error(ArgumentError, /plain basenames/)
    expect do
      store.write_manifest('et', 'en', version: '1', model_file: 'same', vocab_file: 'same')
    end.to raise_error(ArgumentError, /must differ/)
  end

  it 'rejects hostile language codes instead of silently creating colliding paths' do
    expect { store.pack_dir('../evil', 'en') }.to raise_error(ArgumentError, /Invalid translation language code/)
  end
end
