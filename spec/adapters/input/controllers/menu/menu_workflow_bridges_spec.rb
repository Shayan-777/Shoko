# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::WorkflowPortsAdapter do
  let(:catalog) { instance_double('Catalog', start_scan: nil) }
  let(:reader_runner) { double('ReaderRunner', call: nil) }
  let(:mode_switcher) { double('ModeSwitcher', call: nil) }
  let(:annotations_screen) do
    double(
      'AnnotationsScreen',
      refresh_data: nil,
      current_annotation: { id: 1, chapter_index: 0, range: [0, 5], text: 'hi' },
      current_book_path: '/books/a.epub'
    )
  end

  subject(:adapter) do
    described_class.new(
      catalog: catalog,
      mode_switcher: mode_switcher,
      annotations_screen: annotations_screen,
      reader_runner: reader_runner
    )
  end

  it 'delegates refresh_catalog to catalog scanner' do
    adapter.refresh_catalog(force: true)

    expect(catalog).to have_received(:start_scan).with(force: true).once
  end

  it 'reads typed selected annotation from the menu workflow API' do
    selection = adapter.selected_annotation

    expect(selection).to be_a(Shoko::Core::Models::AnnotationSelection)
    expect(selection.id).to eq(1)
    expect(selection.book_path).to eq('/books/a.epub')
  end

  it 'delegates annotation view refresh to the menu workflow API' do
    adapter.refresh_annotations_view

    expect(annotations_screen).to have_received(:refresh_data).once
  end

  it 'delegates reader launch to menu state controller' do
    adapter.run_reader('/books/a.epub')

    expect(reader_runner).to have_received(:call).with('/books/a.epub').once
  end

  it 'delegates switch_mode to menu' do
    adapter.switch_mode(:annotations)

    expect(mode_switcher).to have_received(:call).with(:annotations).once
  end
end
