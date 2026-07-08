# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UseCases::Menu::Actions::Browse do
  def session_store(snapshot)
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuSessionStore
      def initialize(snapshot) = (@snapshot = snapshot)
      def load = @snapshot
      def save(snapshot) = (@snapshot = snapshot)
    end.new(snapshot)
  end

  def transient_store(snapshot)
    Class.new do
      include Shoko::Application::Ports::Outbound::MenuTransientStore
      def initialize(snapshot) = (@snapshot = snapshot)
      def load = @snapshot
      def save(snapshot) = (@snapshot = snapshot)
    end.new(snapshot)
  end

  let(:active) { true }
  let(:done) { 1 } # /done.epub finished, /building.epub in progress, /queued.epub waiting
  let(:selected_source) { '/done.epub' }

  let(:menu_session_store) do
    session_store(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build)
  end
  let(:menu_transient_store) do
    transient_store(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        prepaginate_active: active,
        prepaginate_paths: ['/done.epub', '/building.epub', '/queued.epub'],
        prepaginate_done: done
      )
    )
  end
  let(:reader_launch_service) do
    instance_double('ReaderLaunchService', run_reader: nil, file_not_found: :file_not_found)
  end
  let(:menu_browse_inspection) do
    instance_double('Inspection', selected_library_path: '/open.cache', selected_library_source_path: selected_source)
  end

  subject(:action) do
    described_class.new(
      menu_session_store: menu_session_store,
      menu_browse_inspection: menu_browse_inspection,
      reader_launch_service: reader_launch_service,
      menu_transient_store: menu_transient_store
    )
  end

  describe 'opening a library book while pre-pagination runs' do
    context 'when the selected book is already recalculated' do
      let(:selected_source) { '/done.epub' }

      it 'opens it normally' do
        action.call(:activate_library_selection)
        expect(reader_launch_service).to have_received(:run_reader).with('/open.cache')
      end
    end

    context 'when the selected book is mid-recalculation' do
      let(:selected_source) { '/building.epub' }

      it 'consumes the keypress without opening' do
        expect(action.call(:activate_library_selection)).to eq(:handled)
        expect(reader_launch_service).not_to have_received(:run_reader)
      end
    end

    context 'when the selected book is still queued' do
      let(:selected_source) { '/queued.epub' }

      it 'does not open it' do
        action.call(:activate_library_selection)
        expect(reader_launch_service).not_to have_received(:run_reader)
      end
    end

    context 'when no batch is active' do
      let(:active) { false }
      let(:selected_source) { '/queued.epub' }

      it 'opens normally' do
        action.call(:activate_library_selection)
        expect(reader_launch_service).to have_received(:run_reader).with('/open.cache')
      end
    end
  end

  describe 'browse and library selections are independent' do
    let(:menu_browse_inspection) do
      instance_double('Inspection',
                      browse_item_count: 10, library_item_count: 10,
                      selected_library_path: '/open.cache', selected_library_source_path: selected_source)
    end

    def delta(step)
      Shoko::Application::UseCases::Requests::SelectionDelta.new(delta: step)
    end

    it 'tracks the library cursor separately from the browse cursor' do
      action.call(:move_browse_selection_down, delta(1))
      action.call(:move_library_selection_down, delta(1))
      action.call(:move_library_selection_down, delta(1))

      snapshot = menu_session_store.load
      expect(snapshot.browse_selected).to eq(1)
      expect(snapshot.library_selected).to eq(2)
    end
  end
end
