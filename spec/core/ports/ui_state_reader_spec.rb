# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::UIStateReader do
  let(:implementation) do
    Class.new do
      include Shoko::Core::Ports::UIStateReader
    end.new
  end

  describe 'port interface' do
    it 'defines #terminal_width' do
      expect { implementation.terminal_width }.to raise_error(NotImplementedError)
    end

    it 'defines #terminal_height' do
      expect { implementation.terminal_height }.to raise_error(NotImplementedError)
    end
  end
end
