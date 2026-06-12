# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::EventLoop do
  let(:clock) { double('Clock', monotonic_now: 0.0) }

  def build_reader_state(iterations:)
    remaining = iterations + 1 # the loop checks running? once before iterating
    state = double(
      'ReaderState',
      message: nil,
      mode: :read,
      translator_picker_side: nil,
      notes_composing: false,
      search_landing_highlight: nil
    )
    allow(state).to receive(:running?) { (remaining -= 1) >= 0 }
    state
  end

  def build_controller(render_requests:)
    controller = double(
      'ReaderController',
      perform_first_paint: nil,
      logger: nil,
      read_input_keys: [],
      dispatch_input_keys: nil,
      draw_screen: nil,
      annotation_editor_active?: false,
      recalculating?: false,
      consume_pending_resize?: false,
      drain_async_results: 0,
      async_work_pending?: false
    )
    allow(controller).to receive(:consume_render_request?).and_return(*render_requests, false)
    controller
  end

  it 'redraws when a posted render request is pending, even with no input' do
    controller = build_controller(render_requests: [true])
    state = build_reader_state(iterations: 1)

    described_class.new(controller, state, nil, nil, clock: clock).run

    expect(controller).to have_received(:draw_screen).once
  end

  it 'stays idle when no input, resize, or render request is pending' do
    controller = build_controller(render_requests: [false])
    state = build_reader_state(iterations: 1)

    described_class.new(controller, state, nil, nil, clock: clock).run

    expect(controller).not_to have_received(:draw_screen)
  end

  it 'consumes the render request exactly once per posting' do
    controller = build_controller(render_requests: [true, false])
    state = build_reader_state(iterations: 2)

    described_class.new(controller, state, nil, nil, clock: clock).run

    expect(controller).to have_received(:draw_screen).once
  end
end
