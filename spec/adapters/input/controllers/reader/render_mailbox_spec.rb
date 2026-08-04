# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Reader::RenderMailbox do
  it 'coalesces concurrent requests without losing the pending render' do
    wake_count = 0
    wake_mutex = Mutex.new
    mailbox = described_class.new(wake_input: -> { wake_mutex.synchronize { wake_count += 1 } })

    threads = 8.times.map do
      Thread.new { 100.times { mailbox.request } }
    end
    threads.each(&:join)

    expect(mailbox.consume?).to be(true)
    expect(mailbox.consume?).to be(false)
    expect(wake_count).to eq(800)
  end

  it 'uses a stable relay snapshot while relays are registered concurrently' do
    first = instance_double(Shoko::Application::Services::AsyncResultRelay, drain!: 1, busy?: false)
    second = instance_double(Shoko::Application::Services::AsyncResultRelay, drain!: 2, busy?: true)
    mailbox = described_class.new(wake_input: -> {})
    mailbox.register(first)

    registration = Thread.new { mailbox.register(second) }
    registration.join

    expect(mailbox.drain).to eq(3)
    expect(mailbox.busy?).to be(true)
  end

  it 'rejects nil relays and ignores duplicate registration' do
    relay = instance_double(Shoko::Application::Services::AsyncResultRelay, drain!: 1, busy?: false)
    mailbox = described_class.new(wake_input: -> {})

    expect { mailbox.register(nil) }.to raise_error(ArgumentError, 'relay is required')
    mailbox.register(relay)
    mailbox.register(relay)

    expect(mailbox.drain).to eq(1)
  end
end
