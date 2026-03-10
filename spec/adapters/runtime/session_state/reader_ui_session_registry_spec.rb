# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::ReaderUiSessionRegistry do
  subject(:registry) { described_class.new }

  it 'stores and reads live UI objects by field' do
    popup = Object.new

    registry.write(dictionary_popup: popup, popup_menu: nil)

    expect(registry.read(:dictionary_popup)).to equal(popup)
    expect(registry.read(:popup_menu)).to be_nil
  end

  it 'returns slices for rollback support' do
    popup = Object.new
    registry.write(dictionary_popup: popup, popup_menu: :menu)

    expect(registry.slice(%i[dictionary_popup popup_menu])).to eq(
      dictionary_popup: popup,
      popup_menu: :menu
    )
  end

  it 'clears all live UI fields' do
    registry.write(dictionary_popup: Object.new, popup_menu: :menu)

    registry.clear

    expect(registry.read(:dictionary_popup)).to be_nil
    expect(registry.read(:popup_menu)).to be_nil
  end

  it 'rejects unknown fields' do
    expect { registry.write(unknown_field: Object.new) }.to raise_error(ArgumentError, /Unsupported/)
  end
end
