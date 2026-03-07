# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Shared::TypeCoercion do
  describe '.optional_integer' do
    it 'parses signed integer strings and rejects invalid input' do
      expect(described_class.optional_integer(' 42 ')).to eq(42)
      expect(described_class.optional_integer('-7')).to eq(-7)
      expect(described_class.optional_integer('4.2')).to be_nil
      expect(described_class.optional_integer('')).to be_nil
      expect(described_class.optional_integer(nil)).to be_nil
    end
  end

  describe '.optional_float' do
    it 'parses decimal and exponent strings and rejects invalid input' do
      expect(described_class.optional_float(' 4.25 ')).to eq(4.25)
      expect(described_class.optional_float('1e2')).to eq(100.0)
      expect(described_class.optional_float(7)).to eq(7.0)
      expect(described_class.optional_float('NaN')).to be_nil
      expect(described_class.optional_float('nope')).to be_nil
    end
  end
end
