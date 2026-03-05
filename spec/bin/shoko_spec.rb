# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'bin/shoko' do
  it 'invokes the CLI directly without gem bin recursion' do
    contents = File.read(File.expand_path('../../bin/shoko', __dir__))

    expect(contents).to include('Shoko::Adapters::Input::CLI.run')
    expect(contents).not_to include('Gem.bin_path')
    expect(contents).not_to include('load Gem.bin_path')
  end
end
