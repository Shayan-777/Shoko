# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge do
  let(:controller) { instance_double('ReaderController', request_render: nil) }

  it 'posts the render request through the controller boundary without drawing' do
    bridge = described_class.new(controller: controller)

    expect(controller).to receive(:request_render)

    bridge.request_render(reason: 'pagination.test')
  end
end
