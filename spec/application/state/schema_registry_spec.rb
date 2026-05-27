# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::State::SchemaRegistry do
  let(:terminal_capabilities) do
    instance_double(Shoko::Adapters::Output::TerminalCapabilitiesAdapter, kitty_graphics_supported?: true)
  end

  let(:fragments) do
    [
      Shoko::Core::Reading::Schema,
      Shoko::Application::State::Schema::ReaderProcess,
      Shoko::Application::State::Schema::ReaderPagination,
      Shoko::Application::State::Schema::ReaderView,
      Shoko::Application::State::Schema::MenuProcess,
      Shoko::Application::State::Schema::MenuTransient,
      Shoko::Application::State::Schema::Config,
      Shoko::Application::State::Schema::UiGlobals,
    ]
  end

  let(:registry) do
    fragments.inject(described_class.new) { |reg, fragment| reg.register(fragment) }
  end

  let(:initial_state) { registry.initial_state(terminal_capabilities: terminal_capabilities) }

  it 'rejects fragments that do not respond to contribute' do
    expect { described_class.new.register(Object.new) }
      .to raise_error(described_class::FragmentContractError)
  end

  it 'composes the reader partition from the four reader-side fragments' do
    expected = SpecSupport::StateFixtures::READER_DEFAULTS
    expect(initial_state[:reader]).to eq(expected)
  end

  it 'omits reader-view loading mirror fields from the reader partition' do
    expect(initial_state[:reader]).not_to have_key(:loading_active)
    expect(initial_state[:reader]).not_to have_key(:loading_message)
    expect(initial_state[:reader]).not_to have_key(:loading_progress)
  end

  it 'composes the menu partition from process + transient fragments' do
    expect(initial_state[:menu]).to eq(SpecSupport::StateFixtures::MENU_DEFAULTS)
  end

  it 'composes the config partition with capability-derived overrides' do
    expect(initial_state[:config][:kitty_images]).to be(true)
    base = SpecSupport::StateFixtures::CONFIG_DEFAULTS.merge(kitty_images: true)
    expect(initial_state[:config]).to eq(base)
  end

  it 'composes the UI partition from the UiGlobals fragment' do
    expect(initial_state[:ui]).to eq(SpecSupport::StateFixtures::UI_DEFAULTS)
  end

  it 'keeps menu process and menu transient fields disjoint' do
    intersection = Shoko::Application::State::Schema::MenuProcess::FIELDS &
                   Shoko::Application::State::Schema::MenuTransient::FIELDS
    expect(intersection).to eq([])
  end

  it 'aligns composite snapshot field sets with their fragments' do
    process_fields = Shoko::Application::State::Schema::MenuProcess::FIELDS
    transient_fields = Shoko::Application::State::Schema::MenuTransient::FIELDS
    expect(Shoko::Application::Ports::Outbound::State::MenuSnapshot::FIELDS.sort)
      .to eq((process_fields + transient_fields).sort)

    reading_fields = Shoko::Core::Reading::Schema::FIELDS
    reader_process_fields = Shoko::Application::State::Schema::ReaderProcess::FIELDS
    expect(Shoko::Application::Ports::Outbound::State::ReaderSessionSnapshot::FIELDS.sort)
      .to eq((reading_fields + reader_process_fields).sort)
  end

  it 'rejects fragments whose contribute returns a non-Hash' do
    bad_fragment = Module.new { def self.contribute(_ctx); :not_a_hash; end }
    bad_registry = described_class.new.register(bad_fragment)

    expect { bad_registry.initial_state }
      .to raise_error(described_class::FragmentContractError)
  end
end
