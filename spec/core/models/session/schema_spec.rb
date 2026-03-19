# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Models::Session::Schema do
  it 'keeps snapshot fields and defaults aligned with the canonical schema' do
    expect(Shoko::Core::Models::Session::ReaderSnapshotFields).to eq(described_class::READER_FIELDS)
    expect(Shoko::Core::Models::Session::MenuSnapshotFields).to eq(described_class::MENU_FIELDS)
    expect(Shoko::Core::Models::Session::MenuSessionSnapshotFields).to eq(described_class::MENU_SESSION_FIELDS)
    expect(Shoko::Core::Models::Session::MenuTransientSnapshotFields).to eq(described_class::MENU_TRANSIENT_FIELDS)
    expect(Shoko::Core::Models::Session::ConfigSnapshotFields).to eq(described_class::CONFIG_FIELDS)
    expect(Shoko::Core::Models::Session::ReaderSnapshot::DEFAULTS).to eq(described_class::READER_DEFAULTS)
    expect(Shoko::Core::Models::Session::MenuSnapshot::DEFAULTS).to eq(described_class::MENU_DEFAULTS)
    expect(Shoko::Core::Models::Session::MenuSessionSnapshot::DEFAULTS).to eq(described_class::MENU_SESSION_DEFAULTS)
    expect(Shoko::Core::Models::Session::MenuTransientSnapshot::DEFAULTS).to eq(described_class::MENU_TRANSIENT_DEFAULTS)
    expect(Shoko::Core::Models::Session::ConfigSnapshot::DEFAULTS).to eq(described_class::CONFIG_DEFAULTS)
  end

  it 'builds the initial runtime state from one canonical source' do
    terminal_capabilities = instance_double(
      Shoko::Adapters::Output::TerminalCapabilitiesAdapter,
      kitty_graphics_supported?: true
    )

    state = described_class.initial_runtime_state(terminal_capabilities: terminal_capabilities)

    expect(state[:reader]).to eq(described_class.reader_state_defaults)
    expect(state[:reader]).not_to have_key(:loading_active)
    expect(state[:menu]).to eq(described_class::MENU_DEFAULTS)
    expect(described_class::MENU_SESSION_FIELDS & described_class::MENU_TRANSIENT_FIELDS).to eq([])
    expect((described_class::MENU_SESSION_FIELDS + described_class::MENU_TRANSIENT_FIELDS).sort).to eq(
      described_class::MENU_FIELDS.sort
    )
    expect(state[:config][:kitty_images]).to be(true)
    expect(state[:ui]).to eq(described_class::UI_DEFAULTS)
  end
end
