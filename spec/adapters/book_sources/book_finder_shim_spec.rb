# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::BookSources::BookFinder do
  it 'delegates class-level scan calls to the installed instance and warns' do
    finder = instance_double(described_class, scan_system: [{ 'name' => 'Book' }])
    described_class.install_default(finder)

    expect do
      result = described_class.scan_system(force_refresh: true)
      expect(result).to eq([{ 'name' => 'Book' }])
    end.to output(/DEPRECATION: BookFinder\.scan_system/).to_stderr

    expect(finder).to have_received(:scan_system).with(force_refresh: true)
  end

  it 'delegates class-level cache clearing to the installed instance and warns' do
    finder = instance_double(described_class, clear_cache: nil)
    described_class.install_default(finder)

    expect do
      described_class.clear_cache
    end.to output(/DEPRECATION: BookFinder\.clear_cache/).to_stderr

    expect(finder).to have_received(:clear_cache)
  end
end
