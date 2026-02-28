# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::AppModeRunnerAdapter do
  let(:reader_controller) { instance_double('ReaderController', run: nil) }
  let(:menu_controller) { instance_double('MenuController', run: nil) }
  let(:reader_builder) { instance_double('ReaderBuilder') }
  let(:menu_builder) { instance_double('MenuBuilder') }

  subject(:adapter) do
    described_class.new(
      build_reader_controller: reader_builder,
      build_menu_controller: menu_builder
    )
  end

  it 'runs reader mode through reader builder' do
    allow(reader_builder).to receive(:call).with('/books/a.epub').and_return(reader_controller)

    adapter.run_reader(path: '/books/a.epub')

    expect(reader_builder).to have_received(:call).with('/books/a.epub')
    expect(reader_controller).to have_received(:run)
  end

  it 'runs menu mode through menu builder' do
    allow(menu_builder).to receive(:call).and_return(menu_controller)

    adapter.run_menu

    expect(menu_builder).to have_received(:call)
    expect(menu_controller).to have_received(:run)
  end
end
