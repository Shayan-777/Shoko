# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Core::Services::VersionOrder do
  it 'orders dotted numeric releases numerically' do
    expect(described_class.compare('2.10', '2.9')).to be_positive
    expect(described_class.compare('1.0', '1.0.0')).to eq(0)
  end

  it 'orders natural prerelease suffixes below the final release' do
    expect(described_class.compare('1.0a10', '1.0a2')).to be_positive
    expect(described_class.compare('1.0a10', '1.0')).to be_negative
  end

  it 'reports updates only when the candidate is newer' do
    expect(described_class.newer?('2.0', '1.9')).to be(true)
    expect(described_class.newer?('1.9', '2.0')).to be(false)
  end
end
