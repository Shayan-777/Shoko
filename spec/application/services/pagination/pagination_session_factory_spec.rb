# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::PaginationSessionFactory do
  class PaginationSessionFactorySpecDisplayCapabilities
    def initialize(kitty_images:)
      @kitty_images = kitty_images
    end

    def kitty_images_enabled?(_config_reader)
      @kitty_images
    end
  end

  class PaginationSessionFactorySpecRuntimeContext
    include Shoko::Core::Ports::Outbound::ReaderRuntimeContext

    TerminalSize = Struct.new(:width, :height, keyword_init: true)

    def initialize(display_capabilities_sequence:, terminal_size: TerminalSize.new(width: 80, height: 24))
      @display_capabilities_sequence = display_capabilities_sequence.dup
      @last_display_capabilities = @display_capabilities_sequence.last
      @terminal_size = terminal_size
    end

    def terminal_size
      @terminal_size
    end

    def display_capabilities
      @display_capabilities_sequence.shift || @last_display_capabilities
    end
  end

  let(:config_snapshot) { Struct.new(:view_mode, :line_spacing, :page_numbering_mode).new(:single, :normal, :absolute) }
  let(:pagination_cache) { instance_double('PaginationCache', layout_key: 'cache-key') }
  let(:instrumentation) { instance_double('Instrumentation') }
  let(:reader_session_store) { instance_double('ReaderSessionStore', load: instance_double('ReaderSessionSnapshot')) }
  let(:reader_view_state_store) do
    instance_double('ReaderViewStateStore', load: instance_double('ReaderViewSnapshot'), sidebar_visible?: false)
  end
  let(:reader_pagination_store) { instance_double('ReaderPaginationStore', load: instance_double('ReaderPaginationSnapshot')) }
  let(:app_config_store) { instance_double('AppConfigStore', load: config_snapshot) }
  let(:doc) { instance_double('BookDocument') }
  let(:page_calculator) { instance_double('PageCalculator') }

  it 'rejects runtime contexts that do not implement the outbound port' do
    expect do
      described_class.new(
        reader_runtime_context: Object.new,
        pagination_cache: pagination_cache,
        instrumentation: instrumentation
      )
    end.to raise_error(ArgumentError, /reader_runtime_context must implement/)
  end

  it 'captures fresh display capabilities for each session build' do
    first_capabilities = PaginationSessionFactorySpecDisplayCapabilities.new(kitty_images: false)
    second_capabilities = PaginationSessionFactorySpecDisplayCapabilities.new(kitty_images: true)
    runtime_context = PaginationSessionFactorySpecRuntimeContext.new(
      display_capabilities_sequence: [first_capabilities, second_capabilities]
    )
    factory = described_class.new(
      reader_runtime_context: runtime_context,
      pagination_cache: pagination_cache,
      instrumentation: instrumentation
    )

    first_session = factory.build(
      doc: doc,
      page_calculator: page_calculator,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      dimensions: [100, 40]
    )
    second_session = factory.build(
      doc: doc,
      page_calculator: page_calculator,
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_view_state_store: reader_view_state_store,
      reader_pagination_store: reader_pagination_store,
      dimensions: [100, 40]
    )

    expect(first_session.display_capabilities).to equal(first_capabilities)
    expect(first_session.layout_spec.kitty_images).to be(false)
    expect(second_session.display_capabilities).to equal(second_capabilities)
    expect(second_session.layout_spec.kitty_images).to be(true)
  end
end
