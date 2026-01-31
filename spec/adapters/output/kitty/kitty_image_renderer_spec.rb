# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Kitty::KittyImageRenderer do
  describe '#hashed_id' do
    it 'returns a non-zero 24-bit id' do
      renderer = described_class.new
      id = renderer.send(:hashed_id, 'seed')
      expect(id).to be_between(1, 0xFF_FF_FF)
    end
  end
end
