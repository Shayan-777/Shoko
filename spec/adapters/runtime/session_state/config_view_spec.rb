# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ConfigView do
  class ConfigViewTestConfigStore
    include Shoko::Core::Ports::Outbound::AppConfigStore

    def initialize(snapshot = Shoko::Core::Models::Session::ConfigSnapshot.build)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  it 'reads the current config snapshot dynamically' do
    store = ConfigViewTestConfigStore.new
    view = described_class.new(app_config_store: store)

    expect(view.theme).to eq(:default)
    expect(view.line_spacing).to eq(:normal)

    store.save(store.load.with(theme: :gray, line_spacing: :relaxed))

    expect(view.theme).to eq(:gray)
    expect(view.line_spacing).to eq(:relaxed)
  end
end
