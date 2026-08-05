# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Dictionary::DatasetInstaller do
  let(:entry) { { name: 'en-de.sqlite3', source: 'en', target: 'de' } }
  let(:catalog) { double('DictionaryCatalog', list_remote: [entry]) }
  let(:storage) { double('DictionaryStorage', ensure_databases_path: '/data/dictionaries') }
  let(:config) { double('ConfigSnapshot', dictionary_path: nil) }
  let(:clock) { double('Clock') }
  let(:events) { [] }
  let(:completed) { [] }
  let(:errors) { [] }
  let(:draws) { [] }
  let(:callbacks) do
    {
      publish: ->(**attributes) { events << attributes },
      draw: -> { draws << :draw },
      complete: ->(source, target) { completed << [source, target] },
      error: ->(message) { errors << message },
      normalize: ->(value) { value.to_s.downcase },
    }
  end

  subject(:installer) do
    described_class.new(catalog: catalog, storage: storage, config_reader: config, clock: clock,
                        callbacks: callbacks)
  end

  it 'owns lookup, progress throttling, installation, and completion as one operation' do
    allow(clock).to receive(:monotonic_now).and_return(1.0, 1.01, 1.10)
    allow(catalog).to receive(:download).with(entry, '/data/dictionaries').and_yield(10, 100).and_yield(100, 100)

    expect(installer.install(source: 'en', target: 'de')).to be(true)

    expect(events.map { |event| event[:status] }).to include(
      'Looking for en-de dataset...', 'Downloading en-de.sqlite3... 10%',
      'Downloading en-de.sqlite3... 100%', 'Installed en-de.sqlite3'
    )
    expect(draws).to eq([:draw])
    expect(completed).to eq([%w[en de]])
    expect(errors).to be_empty
  end

  it 'fails cleanly when the catalog has no matching pair' do
    allow(catalog).to receive(:list_remote).and_return([])

    expect(installer.install(source: 'en', target: 'de')).to be(false)
    expect(errors).to eq(['No dictionary dataset found for en-de.'])
    expect(completed).to be_empty
  end
end
