# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Zip::NameNormalizer do
  it 'normalizes backslashes and leading dot slashes' do
    name = '.\\path\\file.txt'
    expect(described_class.normalize(name)).to eq('path/file.txt')
  end
end
