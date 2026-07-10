# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::RenderedContentReaderAdapter do
  let(:state) { instance_double(Shoko::Application::State::StateStore) }
  let(:render_registry) { instance_double(Shoko::Adapters::Ui::RenderRegistry) }
  let(:adapter) { described_class.new(state, render_registry: render_registry) }

  describe '#rendered_lines' do
    it 'returns lines from the render registry' do
      rendered_lines = { left: { 1 => 'line 1' } }
      allow(render_registry).to receive(:lines).and_return(rendered_lines)

      expect(adapter.rendered_lines).to eq(rendered_lines)
    end

    it 'returns an empty hash when the registry has no hash payload' do
      allow(render_registry).to receive(:lines).and_return(nil)

      expect(adapter.rendered_lines).to eq({})
    end

    it 'returns an empty hash when no render registry is configured' do
      expect(described_class.new(state).rendered_lines).to eq({})
    end
  end
end
