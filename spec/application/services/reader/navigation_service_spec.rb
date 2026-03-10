# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Reader::NavigationService do
  class NavigationServiceTestConfigStore
    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end
  end

  class NavigationServiceTestReaderSessionStore
    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  let(:reader_runtime_context) do
    instance_double(
      'ReaderRuntimeContext',
      terminal_size: Shoko::Core::Models::Session::TerminalSize.build(width: 80, height: 24),
      display_capabilities: Shoko::Core::Models::Session::DisplayCapabilitiesSnapshot.build(
        kitty_images_enabled: false
      )
    )
  end

  it 'advances dynamic pagination by updating the reader session snapshot' do
    app_config_store = NavigationServiceTestConfigStore.new(
      Shoko::Core::Models::Session::ConfigSnapshot.build(
        page_numbering_mode: :dynamic,
        view_mode: :single
      )
    )
    reader_session_store = NavigationServiceTestReaderSessionStore.new(
      Shoko::Core::Models::Session::ReaderSnapshot.build(
        current_chapter: 0,
        current_page_index: 0,
        total_chapters: 3
      )
    )
    page_calculator = instance_double('PageCalculator', total_pages: 5)
    allow(page_calculator).to receive(:get_page).with(1).and_return(chapter_index: 0)

    service = described_class.new(
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      page_calculator: page_calculator,
      layout_service: instance_double('LayoutService'),
      wrapped_lines_provider: nil
    )

    service.next_page

    snapshot = reader_session_store.load
    expect(snapshot.current_page_index).to eq(1)
    expect(snapshot.current_chapter).to eq(0)
  end

  it 'advances absolute pagination using layout-derived stride' do
    app_config_store = NavigationServiceTestConfigStore.new(
      Shoko::Core::Models::Session::ConfigSnapshot.build(
        page_numbering_mode: :absolute,
        view_mode: :single,
        line_spacing: :normal
      )
    )
    reader_session_store = NavigationServiceTestReaderSessionStore.new(
      Shoko::Core::Models::Session::ReaderSnapshot.build(
        current_chapter: 0,
        total_chapters: 3,
        current_page: 0,
        single_page: 0,
        page_map: [5, 5, 5]
      )
    )
    layout_service = instance_double('LayoutService', calculate_metrics: [80, 10], adjust_for_line_spacing: 4)

    service = described_class.new(
      app_config_store: app_config_store,
      reader_session_store: reader_session_store,
      reader_runtime_context: reader_runtime_context,
      page_calculator: nil,
      layout_service: layout_service,
      wrapped_lines_provider: nil
    )

    service.next_page

    snapshot = reader_session_store.load
    expect(snapshot.single_page).to eq(4)
    expect(snapshot.current_page).to eq(4)
  end
end
