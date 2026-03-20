# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Runtime::SessionState::MenuLaunchStateAdapter do
  subject(:adapter) { described_class.new }

  it 'stores and clears the last opened path' do
    adapter.last_opened_path = '/books/a.epub'
    expect(adapter.last_opened_path).to eq('/books/a.epub')

    adapter.clear_last_opened_path
    expect(adapter.last_opened_path).to be_nil
  end
end
