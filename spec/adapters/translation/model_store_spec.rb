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

  it 'sanitizes hostile language codes out of pack paths' do
    dir = store.pack_dir('../evil', 'en')
    expect(dir).to eq(File.join(@root, 'evil-en'))
  end
end
