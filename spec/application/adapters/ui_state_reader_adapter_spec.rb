# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::State::UIStateReaderAdapter do
  let(:state) { double('state') }
  let(:adapter) { described_class.new(state) }

  describe '#terminal_width' do
    it 'reads from state' do
      allow(state).to receive(:get).with(%i[ui terminal_width]).and_return(120)
      expect(adapter.terminal_width).to eq(120)
    end

    it 'returns nil when not set' do
      allow(state).to receive(:get).with(%i[ui terminal_width]).and_return(nil)
      expect(adapter.terminal_width).to be_nil
    end
  end

  describe '#terminal_height' do
    it 'reads from state' do
      allow(state).to receive(:get).with(%i[ui terminal_height]).and_return(40)
      expect(adapter.terminal_height).to eq(40)
    end

    it 'returns nil when not set' do
      allow(state).to receive(:get).with(%i[ui terminal_height]).and_return(nil)
      expect(adapter.terminal_height).to be_nil
    end
  end

  describe 'port compliance' do
    it 'includes Application::Ports::UiStateReader' do
      expect(adapter).to be_a(Shoko::Application::Ports::UiStateReader)
    end
  end
end
