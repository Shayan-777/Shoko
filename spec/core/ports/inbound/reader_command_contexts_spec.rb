# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Reader semantic command context contracts' do
  def build_implementation(port_module)
    Class.new do
      include port_module
    end.new
  end

  it 'defines ReaderNavigationCommandContext methods' do
    implementation = build_implementation(Shoko::Core::Ports::Inbound::ReaderNavigationCommandContext)

    expect { implementation.navigation_service }.to raise_error(NotImplementedError)
    expect { implementation.reader_state_reader }.to raise_error(NotImplementedError)
  end

  it 'defines ReaderBookmarkCommandContext methods' do
    implementation = build_implementation(Shoko::Core::Ports::Inbound::ReaderBookmarkCommandContext)

    expect { implementation.bookmark_service }.to raise_error(NotImplementedError)
  end
end
