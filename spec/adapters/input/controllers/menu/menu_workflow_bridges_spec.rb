# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::CatalogRefreshBridge do
  let(:catalog) { instance_double('Catalog', start_scan: nil) }

  subject(:bridge) do
    described_class.new(
      catalog: catalog
    )
  end

  it 'delegates refresh_catalog to catalog scanner' do
    bridge.refresh_catalog(force: true)

    expect(catalog).to have_received(:start_scan).with(force: true).once
  end
end

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::AnnotationSelectionBridge do
  let(:menu) do
    instance_double(
      'MenuController',
      selected_annotation_for_workflow: {
        annotation: { id: 1, chapter_index: 0, range: [0, 5], text: 'hi' },
        book_path: '/books/a.epub'
      }
    )
  end

  it 'reads typed selected annotation from the menu workflow API' do
    bridge = described_class.new(menu: menu)

    selection = bridge.selected_annotation

    expect(selection).to be_a(Shoko::Core::Models::AnnotationSelection)
    expect(selection.id).to eq(1)
    expect(selection.book_path).to eq('/books/a.epub')
  end
end

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::AnnotationViewRefreshBridge do
  let(:menu) { instance_double('MenuController', refresh_annotations_view_for_workflow: nil) }

  it 'delegates annotation view refresh to the menu workflow API' do
    bridge = described_class.new(menu: menu)
    bridge.refresh_annotations_view

    expect(menu).to have_received(:refresh_annotations_view_for_workflow).once
  end
end

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::ReaderRunnerBridge do
  let(:state_controller) { instance_double('MenuStateController', run_reader: nil) }
  let(:menu) { instance_double('MenuController', state_controller: state_controller) }

  it 'delegates reader launch to menu state controller' do
    bridge = described_class.new(menu: menu)
    bridge.run_reader('/books/a.epub')

    expect(state_controller).to have_received(:run_reader).with('/books/a.epub').once
  end
end
