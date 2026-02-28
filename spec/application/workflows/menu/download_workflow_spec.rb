# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::DownloadWorkflow do
  class PortMenuWorkflowStateWriterDouble
    include Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter

    def set_download_state(_attrs); end
    def set_dictionary_state(_attrs); end
    def set_annotation_state(_attrs); end
    def set_loading_state(path: nil, active: nil, progress: nil, message: nil, index: nil, mode: nil); end
  end

  let(:download_service) { instance_double('DownloadService') }
  let(:menu_state_writer) { instance_spy(PortMenuWorkflowStateWriterDouble) }
  let(:menu_runtime) { instance_spy('MenuRuntime', draw_screen: nil, refresh_scan: nil) }
  let(:clock) { instance_double('Clock', monotonic_now: 1.0) }

  before do
    allow(menu_state_writer).to receive(:is_a?).and_return(false)
    allow(menu_state_writer).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MenuWorkflowStateWriter)
      .and_return(true)

    allow(menu_runtime).to receive(:is_a?).and_return(false)
    allow(menu_runtime).to receive(:is_a?)
      .with(Shoko::Core::Ports::Outbound::MenuWorkflowRuntime)
      .and_return(true)
  end

  subject(:workflow) do
    described_class.new(
      download_service: download_service,
      menu_state_writer: menu_state_writer,
      menu_runtime: menu_runtime,
      clock: clock
    )
  end

  it 'requires menu_runtime' do
    expect do
      described_class.new(
        download_service: download_service,
        menu_state_writer: menu_state_writer,
        menu_runtime: nil,
        clock: clock
      )
    end.to raise_error(ArgumentError, 'menu_runtime is required')
  end

  describe '#download_book' do
    let(:book) { { title: 'Pride and Prejudice' } }

    it 'refreshes catalog scan through runtime bridge after successful download' do
      allow(download_service).to receive(:download) do |_book, &block|
        block&.call(1, 1)
        { path: '/tmp/books/pride.epub', existing: false }
      end

      workflow.download_book(book)

      expect(download_service).to have_received(:download).with(book)
      expect(menu_runtime).to have_received(:refresh_scan).with(force: true)
      expect(menu_state_writer).to have_received(:set_download_state).at_least(:once)
    end
  end
end
