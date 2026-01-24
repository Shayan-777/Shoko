# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Ports::RenderStateWriter do
  let(:implementation) do
    Class.new do
      include Shoko::Core::Ports::RenderStateWriter
    end.new
  end

  describe 'port interface' do
    it 'defines #clear_rendered_lines' do
      expect { implementation.clear_rendered_lines }.to raise_error(NotImplementedError)
    end

    it 'defines #update_rendered_lines' do
      expect { implementation.update_rendered_lines({}) }.to raise_error(NotImplementedError)
    end
  end
end
