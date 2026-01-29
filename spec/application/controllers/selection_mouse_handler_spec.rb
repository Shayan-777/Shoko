# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::SelectionMouseHandler do
  class DummySelectionHandler
    include Shoko::Application::Controllers::SelectionMouseHandler

    def initialize(state)
      @state = state
    end

    attr_reader :state
  end

  class FakeState
    def initialize(backend)
      @backend = backend
    end

    def get(path)
      return @backend if path == %i[config dictionary_backend]

      nil
    end
  end

  let(:handler) { DummySelectionHandler.new(state) }

  describe '#dictionary_lookup_available?' do
    before do
      allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:databases_present?).and_return(false)
    end

    context 'when dictionary backend is disabled' do
      let(:state) { FakeState.new(:disabled) }

      it 'returns false even if sqlite3 is installed' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

        with_env('SHOKO_DICTIONARY' => nil) do
          expect(handler.send(:dictionary_lookup_available?)).to be(false)
        end
      end
    end

    context 'when dictionary backend is auto and no databases are present' do
      let(:state) { FakeState.new(nil) }

      it 'returns false even if sqlite3 is installed' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

        with_env('SHOKO_DICTIONARY' => nil) do
          expect(handler.send(:dictionary_lookup_available?)).to be(false)
        end
      end
    end

    context 'when dictionary backend is auto and databases are present' do
      let(:state) { FakeState.new(nil) }

      it 'returns true when sqlite3 is available' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:databases_present?).and_return(true)

        with_env('SHOKO_DICTIONARY' => nil) do
          expect(handler.send(:dictionary_lookup_available?)).to be(true)
        end
      end
    end

    context 'when dictionary backend is enabled' do
      let(:state) { FakeState.new(:sqlite) }

      it 'returns true when sqlite3 is available' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

        with_env('SHOKO_DICTIONARY' => nil) do
          expect(handler.send(:dictionary_lookup_available?)).to be(true)
        end
      end

      it 'returns false when sqlite3 is missing' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(false)

        with_env('SHOKO_DICTIONARY' => nil) do
          expect(handler.send(:dictionary_lookup_available?)).to be(false)
        end
      end
    end

    context 'when enabled via environment variable' do
      let(:state) { FakeState.new(nil) }

      it 'returns true when sqlite3 is available' do
        allow(Shoko::Adapters::Storage::SqliteDictionaryAdapter).to receive(:sqlite3_available?).and_return(true)

        with_env('SHOKO_DICTIONARY' => 'sqlite') do
          expect(handler.send(:dictionary_lookup_available?)).to be(true)
        end
      end
    end
  end
end
