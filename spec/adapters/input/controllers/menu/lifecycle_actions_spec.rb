# frozen_string_literal: true

require 'spec_helper'

# The menu controller's run-loop helpers were formerly extracted into an
# Actions::Lifecycle mixin; they are now plain Controller methods. Exercise them
# without the heavy real constructor via a subclass that sets only the ivars they use.
RSpec.describe Shoko::Adapters::Input::Controllers::Menu::Controller do
  let(:harness_class) do
    Class.new(described_class) do
      attr_reader :filtered_epubs

      def initialize(catalog:, terminal_service:, main_menu_component:, menu_state_reader:)
        @catalog = catalog
        @terminal_service = terminal_service
        @main_menu_component = main_menu_component
        @menu_state_reader = menu_state_reader
      end
    end
  end

  let(:browse_screen) { Struct.new(:filtered_epubs).new }
  let(:main_menu_component) do
    screen = browse_screen
    Class.new { define_method(:browse_screen) { screen } }.new
  end

  it 'renders cached entries immediately and starts a preserved background refresh' do
    entries = [{ 'path' => '/books/cached.epub', 'name' => 'Cached' }]
    catalog = double('Catalog')
    terminal = double('TerminalService', setup: nil)
    state = double('MenuStateReader', mode: :browse)
    allow(catalog).to receive(:load_cached)
    allow(catalog).to receive(:entries).and_return(entries)
    allow(catalog).to receive(:start_scan)

    harness = harness_class.new(
      catalog: catalog,
      terminal_service: terminal,
      main_menu_component: main_menu_component,
      menu_state_reader: state
    )

    harness.send(:bootstrap_catalog)

    expect(browse_screen.filtered_epubs).to eq(entries)
    expect(harness.filtered_epubs).to eq(entries)
    expect(catalog).to have_received(:start_scan).with(force: true, preserve_entries: true)
  end

  it 'polls input while a catalog scan is in progress' do
    catalog = double('Catalog', scan_status: :scanning)
    state = double('MenuStateReader', mode: :browse)
    harness = harness_class.new(
      catalog: catalog,
      terminal_service: double('TerminalService'),
      main_menu_component: main_menu_component,
      menu_state_reader: state
    )

    expect(harness.input_poll_interval).to eq(0.1)
  end
end
