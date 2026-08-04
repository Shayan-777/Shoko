# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge do
  let(:controller) { instance_double(Shoko::Adapters::Input::Controllers::ReaderController, request_render: nil) }

  it 'posts the render request through the controller boundary without drawing' do
    bridge = described_class.new(controller: controller)

    expect(controller).to receive(:request_render)

    bridge.request_render(reason: 'pagination.test')
  end

  it 'translates posting failures into the outbound port error' do
    bridge = described_class.new(controller: controller)
    allow(controller).to receive(:request_render).and_raise(IOError, 'wake pipe closed')

    expect do
      bridge.request_render(reason: 'pagination.test')
    end.to raise_error(
      Shoko::Application::Ports::Outbound::ReaderRenderRequester::RenderRequestError,
      /pagination\.test.*wake pipe closed/
    )
  end
end
