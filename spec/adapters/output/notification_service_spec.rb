# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::NotificationService do
  let(:writer) { instance_double(Shoko::Application::Ports::Outbound::NotificationWriter) }

  describe '#set_message' do
    it 'shows messages through the injected notification writer' do
      service = described_class.new(notification_writer: writer)
      allow(writer).to receive(:show_message)

      service.set_message('Copied to clipboard', 2)

      expect(writer).to have_received(:show_message).with('Copied to clipboard')
    end

    it 'clears immediately when duration is zero' do
      service = described_class.new(notification_writer: writer)
      allow(writer).to receive(:show_message)
      allow(writer).to receive(:clear_message)

      service.set_message('Short lived', 0)

      expect(writer).to have_received(:show_message).with('Short lived')
      expect(writer).to have_received(:clear_message)
    end
  end

  describe '#tick' do
    it 'clears elapsed messages' do
      service = described_class.new(notification_writer: writer)
      allow(writer).to receive(:show_message)
      allow(writer).to receive(:clear_message)
      now = 1000.0
      later = now + 3.0
      allow(Process).to receive(:clock_gettime)
        .with(Process::CLOCK_MONOTONIC)
        .and_return(now, later)

      service.set_message('Toast', 2)
      service.tick

      expect(writer).to have_received(:clear_message).once
    end
  end
end
