# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::AppModeRunnerAdapter do
  let(:reader_mode_runner) { instance_double(Shoko::Adapters::Runtime::ReaderModeRunner, run: nil) }
  let(:menu_controller) { instance_double(Shoko::Adapters::Input::Controllers::Menu::Controller, run: nil) }
  let(:menu_builder) { instance_double(Proc) }

  subject(:adapter) do
    described_class.new(
      reader_mode_runner: reader_mode_runner,
      build_menu_controller: menu_builder
    )
  end

  it 'runs reader mode through the runtime runner' do
    adapter.run_reader(path: '/books/a.epub')

    expect(reader_mode_runner).to have_received(:run).with(path: '/books/a.epub')
  end

  it 'runs menu mode through menu builder' do
    allow(menu_builder).to receive(:call).and_return(menu_controller)

    adapter.run_menu

    expect(menu_builder).to have_received(:call)
    expect(menu_controller).to have_received(:run)
  end
end
