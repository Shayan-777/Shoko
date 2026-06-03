# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::KeyDefinitions do
  it 'exposes canonical key groups for navigation, actions, reader, and menu' do
    expect(described_class::NAVIGATION.keys).to include(:up, :down, :left, :right)
    expect(described_class::ACTIONS.keys).to include(:confirm, :cancel, :quit, :backspace)
    expect(described_class::READER.keys).to include(:next_page, :prev_page, :in_book_search)
    expect(described_class::MENU.keys).to include(:browse, :download_books, :settings)
    expect(described_class::Helpers).to respond_to(:navigation_key?)
  end

  it 'activates in-book search with "/"' do
    expect(described_class::READER[:in_book_search]).to eq(['/'])
  end
end
