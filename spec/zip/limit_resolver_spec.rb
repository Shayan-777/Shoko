# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Zip::LimitResolver do
  it 'uses the provided value when valid' do
    expect(described_class.resolve(10, default: 5)).to eq(10)
  end

  it 'falls back to default when value is nil' do
    expect(described_class.resolve(nil, default: 5)).to eq(5)
  end

  it 'raises for invalid values' do
    expect { described_class.resolve('nope', default: 5) }.to raise_error(ArgumentError)
  end
end
