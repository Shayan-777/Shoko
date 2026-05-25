# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/input/controllers/menu/actions/lifecycle_actions'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::Actions::Lifecycle do
  class MenuLifecycleActionsSpecHarness
    include Shoko::Adapters::Input::Controllers::Menu::Actions::Lifecycle

    attr_reader :filtered_epubs

    def initialize(catalog:, terminal_service:, main_menu_component:, menu_state_reader:)
      @catalog = catalog
      @terminal_service = terminal_service
      @main_menu_component = main_menu_component
      @menu_state_reader = menu_state_reader
    end
  end

  class MenuLifecycleActionsSpecBrowseScreen
    attr_accessor :filtered_epubs
  end

  class MenuLifecycleActionsSpecMenuComponent
    attr_reader :browse_screen

    def initialize
      @browse_screen = MenuLifecycleActionsSpecBrowseScreen.new
    end
  end

  it 'renders cached entries immediately and starts a preserved background refresh' do
    entries = [{ 'path' => '/books/cached.epub', 'name' => 'Cached' }]
    catalog = double('Catalog')
    terminal = double('TerminalService', setup: nil)
    component = MenuLifecycleActionsSpecMenuComponent.new
    state = double('MenuStateReader', mode: :browse)
    allow(catalog).to receive(:load_cached)
    allow(catalog).to receive(:entries).and_return(entries)
    allow(catalog).to receive(:start_scan)

    harness = MenuLifecycleActionsSpecHarness.new(
      catalog: catalog,
      terminal_service: terminal,
      main_menu_component: component,
      menu_state_reader: state
    )

    harness.send(:bootstrap_catalog)

    expect(component.browse_screen.filtered_epubs).to eq(entries)
    expect(harness.filtered_epubs).to eq(entries)
    expect(catalog).to have_received(:start_scan).with(force: true, preserve_entries: true)
  end

  it 'polls input while a catalog scan is in progress' do
    catalog = double('Catalog', scan_status: :scanning)
    terminal = double('TerminalService')
    component = MenuLifecycleActionsSpecMenuComponent.new
    state = double('MenuStateReader', mode: :browse)
    harness = MenuLifecycleActionsSpecHarness.new(
      catalog: catalog,
      terminal_service: terminal,
      main_menu_component: component,
      menu_state_reader: state
    )

    expect(harness.input_poll_interval).to eq(0.1)
  end
end
