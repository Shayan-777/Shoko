# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::State::StateStore do
  let(:terminal_capabilities) { Shoko::Adapters::Output::Terminal::NullTerminalCapabilities.new }
  let(:config_dir) { @tmpdir || Dir.tmpdir }
  let(:config_file) { File.join(config_dir, 'config.json') }
  let(:config_storage) do
    storage = Object.new
    dir = config_dir
    file = config_file
    storage.define_singleton_method(:config_dir) { dir }
    storage.define_singleton_method(:config_file) { file }
    storage.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
    storage.define_singleton_method(:atomic_write) do |path, data|
      File.write(path, data)
    end
    storage.define_singleton_method(:read_file) do |path|
      File.exist?(path) ? File.read(path) : nil
    end
    storage.define_singleton_method(:file_exist?) do |path|
      File.exist?(path)
    end
    storage
  end
  let(:schema_registry) do
    Shoko::Application::State::SchemaRegistry.new
      .register(Shoko::Core::Reading::Schema)
      .register(Shoko::Application::State::Schema::ReaderProcess)
      .register(Shoko::Application::State::Schema::ReaderPagination)
      .register(Shoko::Application::State::Schema::ReaderView)
      .register(Shoko::Application::State::Schema::MenuProcess)
      .register(Shoko::Application::State::Schema::MenuTransient)
      .register(Shoko::Application::State::Schema::Config)
      .register(Shoko::Application::State::Schema::UiGlobals)
  end
  let(:store) do
    described_class.new(
      config_storage: config_storage,
      terminal_capabilities: terminal_capabilities,
      schema_registry: schema_registry
    )
  end

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  describe 'StateUpdateError' do
    it 'captures state transition context' do
      error = described_class::StateUpdateError.new(
        'Test error',
        old_state: { a: 1 },
        new_state: { a: 2 },
        updates: { [:a] => 2 },
        reason: 'test reason'
      )

      expect(error.message).to eq('Test error')
      expect(error.old_state).to eq({ a: 1 })
      expect(error.new_state).to eq({ a: 2 })
      expect(error.updates).to eq({ [:a] => 2 })
      expect(error.reason).to eq('test reason')
    end
  end

  describe '#valid_transition?' do
    context 'reader transitions' do
      it 'rejects negative left_page' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader left_page] => -1 })
        expect(result).to eq('left_page cannot be negative')
      end

      it 'rejects negative right_page' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader right_page] => -5 })
        expect(result).to eq('right_page cannot be negative')
      end

      it 'rejects negative single_page' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader single_page] => -10 })
        expect(result).to eq('single_page cannot be negative')
      end

      it 'rejects negative current_page_index' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader current_page_index] => -1 })
        expect(result).to eq('current_page_index cannot be negative')
      end

      it 'allows valid page values' do
        result = store.send(:valid_transition?, {}, {}, {
                              %i[reader left_page] => 0,
                              %i[reader right_page] => 10,
                              %i[reader single_page] => 5,
                            })
        expect(result).to be true
      end

      it 'rejects current_chapter exceeding total_chapters' do
        new_state = { reader: { total_chapters: 5 } }
        result = store.send(:valid_transition?, {}, new_state, { %i[reader current_chapter] => 5 })
        expect(result).to eq('current_chapter (5) cannot exceed total_chapters (5)')
      end

      it 'allows current_chapter within bounds' do
        new_state = { reader: { total_chapters: 5 } }
        result = store.send(:valid_transition?, {}, new_state, { %i[reader current_chapter] => 4 })
        expect(result).to be true
      end

      it 'allows current_chapter when total_chapters is 0' do
        new_state = { reader: { total_chapters: 0 } }
        result = store.send(:valid_transition?, {}, new_state, { %i[reader current_chapter] => 3 })
        expect(result).to be true
      end
    end

    context 'pagination transitions' do
      it 'rejects current_page_index exceeding dynamic_total_pages' do
        new_state = { reader: { dynamic_total_pages: 10 } }
        result = store.send(:valid_transition?, {}, new_state, { %i[reader current_page_index] => 10 })
        expect(result).to eq('current_page_index (10) cannot exceed dynamic_total_pages (10)')
      end

      it 'allows current_page_index within bounds' do
        new_state = { reader: { dynamic_total_pages: 10 } }
        result = store.send(:valid_transition?, {}, new_state, { %i[reader current_page_index] => 9 })
        expect(result).to be true
      end

      it 'rejects negative total_pages' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader total_pages] => -1 })
        expect(result).to eq('total_pages cannot be negative')
      end

      it 'rejects negative dynamic_total_pages' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader dynamic_total_pages] => -5 })
        expect(result).to eq('dynamic_total_pages cannot be negative')
      end
    end

    context 'overlay transitions' do
      it 'rejects negative annotations_overlay_selected' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader annotations_overlay_selected] => -1 })
        expect(result).to eq('annotations_overlay_selected cannot be negative')
      end

      it 'allows non-negative annotations_overlay_selected' do
        result = store.send(:valid_transition?, {}, {}, { %i[reader annotations_overlay_selected] => 2 })
        expect(result).to be true
      end
    end
  end

  describe '#update with validation' do
    it 'raises StateUpdateError for invalid transitions' do
      expect do
        store.update({ %i[reader left_page] => -1 })
      end.to raise_error(described_class::StateUpdateError, 'left_page cannot be negative')
    end

    it 'includes context in StateUpdateError' do
      store.update({ %i[reader single_page] => -5 })
    rescue described_class::StateUpdateError => e
      expect(e.updates).to eq({ %i[reader single_page] => -5 })
      expect(e.reason).to eq('single_page cannot be negative')
    end

    it 'allows valid transitions' do
      expect { store.update({ %i[reader left_page] => 10 }) }.not_to raise_error
      expect(store.get(%i[reader left_page])).to eq(10)
    end

    it 'does not update state on invalid transition' do
      original_value = store.get(%i[reader left_page])
      begin
        store.update({ %i[reader left_page] => -1 })
      rescue described_class::StateUpdateError
        # Expected
      end
      expect(store.get(%i[reader left_page])).to eq(original_value)
    end
  end

  describe '#handle_invalid_transition' do
    it 'raises StateUpdateError with string reason' do
      expect do
        store.handle_invalid_transition({}, {}, {}, 'Custom error message')
      end.to raise_error(described_class::StateUpdateError, 'Custom error message')
    end

    it 'raises StateUpdateError with default message for boolean false' do
      expect do
        store.handle_invalid_transition({}, {}, {}, false)
      end.to raise_error(described_class::StateUpdateError, 'Invalid state transition')
    end
  end

  describe 'subclass customization' do
    let(:silent_store_class) do
      Class.new(described_class) do
        attr_reader :last_invalid_transition

        def handle_invalid_transition(old_state, new_state, updates, reason)
          @last_invalid_transition = { old_state: old_state, new_state: new_state, updates: updates, reason: reason }
          # Don't raise - just log and skip
        end
      end
    end

    it 'allows subclasses to customize invalid transition handling' do
      silent_store = silent_store_class.new(config_storage: config_storage, terminal_capabilities: terminal_capabilities, schema_registry: schema_registry)
      expect { silent_store.update({ %i[reader left_page] => -1 }) }.not_to raise_error

      expect(silent_store.last_invalid_transition).to include(
        updates: { %i[reader left_page] => -1 },
        reason: 'left_page cannot be negative'
      )
      # State should not be updated
      expect(silent_store.get(%i[reader left_page])).to eq(0)
    end
  end
end
