# frozen_string_literal: true

require 'spec_helper'
require 'shoko/adapters/ui/components/status_bar/format_badge'

RSpec.describe Shoko::Adapters::Ui::Components::StatusBar::FormatBadge do
  describe '.for_format' do
    it 'colors epub green and labels it EPUB' do
      badge = described_class.for_format(:epub)
      expect(badge.label).to eq('EPUB')
      expect(badge.rgb).to eq([63, 185, 80])
    end

    it 'colors pdf red' do
      expect(described_class.for_format(:pdf).rgb).to eq([240, 90, 82])
    end

    it 'colors rtf blue' do
      expect(described_class.for_format(:rtf).rgb).to eq([56, 139, 253])
    end

    it 'colors fb2 purple' do
      expect(described_class.for_format(:fb2).rgb).to eq([188, 140, 255])
    end

    it 'colors every kindle format orange while keeping the precise label' do
      %i[mobi azw azw3].each do |ext|
        badge = described_class.for_format(ext)
        expect(badge.rgb).to eq([229, 148, 58])
        expect(badge.label).to eq(ext.to_s.upcase)
      end
    end

    it 'returns nil for a blank or missing format' do
      expect(described_class.for_format(nil)).to be_nil
      expect(described_class.for_format('')).to be_nil
    end
  end

  describe '.format_for_path' do
    it 'detects the extension case-insensitively' do
      expect(described_class.format_for_path('/books/Gatsby.EPUB')).to eq(:epub)
    end

    it 'handles the compound fb2.zip extension' do
      expect(described_class.format_for_path('/books/War.fb2.zip')).to eq(:fb2)
    end

    it 'returns nil when there is no usable extension' do
      expect(described_class.format_for_path('/books/no-extension')).to be_nil
      expect(described_class.format_for_path(nil)).to be_nil
    end
  end

  describe '.mode_badge' do
    it 'splits into a mode compartment and a lowercase format compartment, keeping the format color' do
      badge = described_class.mode_badge('Reader', :epub)
      expect(badge.mode).to eq('Reader')
      expect(badge.label).to eq('epub')
      expect(badge.rgb).to eq([63, 185, 80])
    end

    it 'reflects the search mode' do
      badge = described_class.mode_badge('Search', :pdf)
      expect(badge.mode).to eq('Search')
      expect(badge.label).to eq('pdf')
    end

    it 'falls back to a single brand badge when the format is unknown' do
      badge = described_class.mode_badge('Reader', nil)
      expect(badge.label).to eq('READER')
      expect(badge.mode).to be_nil
      expect(badge.rgb).to eq(Shoko::Adapters::Ui::Components::StatusBar::Palette::BRAND_RGB)
    end
  end

  describe '.view_badge' do
    it 'builds a brand-accented badge from an uppercased label' do
      badge = described_class.view_badge('browse')
      expect(badge.label).to eq('BROWSE')
      expect(badge.rgb).to eq(Shoko::Adapters::Ui::Components::StatusBar::Palette::BRAND_RGB)
    end

    it 'returns nil for a blank label' do
      expect(described_class.view_badge('  ')).to be_nil
    end
  end
end
