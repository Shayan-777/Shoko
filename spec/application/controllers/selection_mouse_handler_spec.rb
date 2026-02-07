# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Controllers::SelectionMouseHandler do
  class DummySelectionHandler
    include Shoko::Application::Controllers::SelectionMouseHandler

    def initialize(config_reader, dict_avail)
      @config_reader = config_reader
      @dictionary_availability = dict_avail
    end
  end

  class FakeConfigReader
    def initialize(backend)
      @backend = backend
    end

    def dictionary_backend
      @backend
    end

    def dictionary_path
      nil
    end
  end

  class FakeDictAvailability
    def initialize(sqlite3_available:, databases_present: false, env_override_enabled: false)
      @sqlite3_available = sqlite3_available
      @databases_present = databases_present
      @env_override_enabled = env_override_enabled
    end

    def sqlite3_available?
      @sqlite3_available
    end

    def databases_present?(_path)
      @databases_present
    end

    def env_override_enabled?
      @env_override_enabled
    end
  end

  let(:dict_avail) { FakeDictAvailability.new(sqlite3_available: true, databases_present: false) }
  let(:handler) { DummySelectionHandler.new(config_reader, dict_avail) }

  describe '#dictionary_lookup_available?' do
    context 'when dictionary backend is disabled' do
      let(:config_reader) { FakeConfigReader.new(:disabled) }

      it 'returns false even if sqlite3 is installed' do
        expect(handler.send(:dictionary_lookup_available?)).to be(false)
      end
    end

    context 'when dictionary backend is auto and no databases are present' do
      let(:config_reader) { FakeConfigReader.new(nil) }

      it 'returns false even if sqlite3 is installed' do
        expect(handler.send(:dictionary_lookup_available?)).to be(false)
      end
    end

    context 'when dictionary backend is auto and databases are present' do
      let(:config_reader) { FakeConfigReader.new(nil) }
      let(:dict_avail) { FakeDictAvailability.new(sqlite3_available: true, databases_present: true) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end
    end

    context 'when dictionary backend is enabled' do
      let(:config_reader) { FakeConfigReader.new(:sqlite) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end

      it 'returns false when sqlite3 is missing' do
        let_dict = FakeDictAvailability.new(sqlite3_available: false)
        h = DummySelectionHandler.new(config_reader, let_dict)

        expect(h.send(:dictionary_lookup_available?)).to be(false)
      end
    end

    context 'when enabled via environment variable override' do
      let(:config_reader) { FakeConfigReader.new(nil) }
      let(:dict_avail) { FakeDictAvailability.new(sqlite3_available: true, env_override_enabled: true) }

      it 'returns true when sqlite3 is available' do
        expect(handler.send(:dictionary_lookup_available?)).to be(true)
      end
    end
  end
end
