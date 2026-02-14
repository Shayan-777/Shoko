# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Kitty::KittyImageRenderer do
  describe '#hashed_id' do
    it 'returns a non-zero 24-bit id' do
      dummy_loader = Shoko::Adapters::Output::Kitty::ResourceLoader.new(loader: double('EpubResourceLoader'))
      renderer = described_class.new(resource_loader: dummy_loader)
      id = renderer.send(:hashed_id, 'seed')
      expect(id).to be_between(1, 0xFF_FF_FF)
    end
  end
end
