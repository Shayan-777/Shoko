# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Policies::ThemePolicy do
  describe '.normalize' do
    it 'normalizes canonical ids and legacy aliases' do
      expect(described_class.normalize(:sepia)).to eq(:sepia)
      expect(described_class.normalize(:dark)).to eq(:default)
      expect(described_class.normalize('light')).to eq(:gray)
      expect(described_class.normalize(:standard)).to eq(:default)
    end

    it 'returns nil for unsupported values' do
      expect(described_class.normalize(:unknown_theme)).to be_nil
      expect(described_class.normalize(nil)).to be_nil
    end
  end

  describe '.valid?' do
    it 'accepts canonical ids and aliases' do
      expect(described_class.valid?(:default)).to be(true)
      expect(described_class.valid?(:dark)).to be(true)
    end

    it 'rejects unsupported themes' do
      expect(described_class.valid?(:unknown_theme)).to be(false)
    end
  end
end
