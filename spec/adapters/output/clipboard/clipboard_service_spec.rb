# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Clipboard::ClipboardService do
  subject(:service) { described_class.new }

  describe '#read_available?' do
    it 'returns true when a clipboard read command is detected' do
      allow(service).to receive(:detect_read_command).and_return(['pbpaste'])

      expect(service.read_available?).to be(true)
    end
  end

  describe '#read_with_feedback' do
    it 'returns clipboard text and emits a paste message' do
      allow(service).to receive(:detect_read_command).and_return(['pbpaste'])
      allow(service).to receive(:clipboard_read_output).with(['pbpaste']).and_return('bonjour')

      message = nil
      result = service.read_with_feedback { |text| message = text }

      expect(result).to eq('bonjour')
      expect(message).to eq(' Pasted from clipboard')
    end

    it 'returns nil and emits an empty message when the clipboard has no text' do
      allow(service).to receive(:detect_read_command).and_return(['pbpaste'])
      allow(service).to receive(:clipboard_read_output).with(['pbpaste']).and_return('')

      message = nil
      result = service.read_with_feedback { |text| message = text }

      expect(result).to be_nil
      expect(message).to eq(' Clipboard is empty')
    end
  end
end
