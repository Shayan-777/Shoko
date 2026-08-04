# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::BarOverlayMouseRouter do
  let(:popup) { double('OverlayPopup', hit_test: 2) }
  let(:reader_state_reader) do
    double('ReaderState', mode: :in_book_search, in_book_search_popup: popup, overlay_hover_index: nil)
  end
  let(:reader_session_mutator) { double('ReaderMutator', update_reader: nil) }
  let(:coordinate_service) { double('CoordinateService', mouse_to_terminal: { x: 4, y: 6 }) }
  let(:dispatch_keys) { instance_double(Proc, call: nil) }
  let(:dispatch_intent) { instance_double(Proc, call: nil) }
  let(:draw) { instance_double(Proc, call: nil) }

  subject(:router) do
    described_class.new(
      reader_state_reader: reader_state_reader,
      reader_session_mutator: reader_session_mutator,
      coordinate_service: coordinate_service,
      dispatch_keys: dispatch_keys,
      dispatch_intent: dispatch_intent,
      draw: draw
    )
  end

  it 'leaves normal reading-mode pointer events unconsumed' do
    allow(reader_state_reader).to receive(:mode).and_return(:read)

    expect(router.handle(button: 0, released: true, x: 3, y: 5)).to be(false)
  end

  it 'routes wheel events through the keyboard path' do
    expect(router.handle(button: 64, released: false, x: 3, y: 5)).to be(true)

    expect(dispatch_keys).to have_received(:call).with(["\e[A"])
    expect(draw).to have_received(:call)
  end

  it 'moves overlay selection on a left-button press' do
    router.handle(button: 0, released: false, x: 3, y: 5)

    expect(reader_session_mutator).to have_received(:update_reader).with(
      search_selected_index: 2, overlay_hover_index: nil
    )
  end
end
