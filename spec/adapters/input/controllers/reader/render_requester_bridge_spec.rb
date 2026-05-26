# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge do
  let(:controller) { instance_double('ReaderController', force_redraw: nil, draw_screen: nil) }
  let(:logger) { instance_double('Logger', debug: nil) }

  it 'requests redraw through the controller boundary' do
    bridge = described_class.new(controller: controller, logger: logger)

    expect(controller).to receive(:force_redraw).ordered
    expect(controller).to receive(:draw_screen).ordered

    bridge.request_render(reason: 'pagination.test')
  end

  it 'raises typed render request errors when controller redraw fails' do
    allow(controller).to receive(:draw_screen).and_raise(RuntimeError, 'boom')
    bridge = described_class.new(controller: controller, logger: logger)

    expect(logger).to receive(:debug).with('reader.render_request.failed',
                                           reason: 'pagination.test',
                                           error: 'RuntimeError',
                                           message: 'boom')
    expect do
      bridge.request_render(reason: 'pagination.test')
    end.to raise_error(Shoko::Application::Ports::Outbound::ReaderRenderRequester::RenderRequestError, /boom/)
  end
end
