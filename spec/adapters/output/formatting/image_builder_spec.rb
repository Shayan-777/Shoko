# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Output::Formatting::FormattingService::LineAssembler::ImageBuilder do
  let(:block) do
    Shoko::Core::Models::ContentBlock.new(
      type: :image, segments: [], metadata: { image: { src: 'image0001.jpg', alt: 'page' } }
    )
  end

  def builder(width:, max_image_rows:)
    described_class.new(width: width, chapter_index: 0, chapter_source_path: 'kindle-content.xhtml',
                        max_image_rows: max_image_rows)
  end

  describe 'block image sizing' do
    it 'lets a block image use the full page height so high-resolution images fill the screen' do
      lines = builder(width: 120, max_image_rows: 48).block_lines(block, block_index: 0, base_metadata: {})

      expect(lines.length).to eq(48)
      expect(lines.first.metadata[:image_render][:rows]).to eq(48)
    end

    it 'scales the row budget with the page height rather than a fixed cap' do
      rows = builder(width: 200, max_image_rows: 56).block_lines(block, block_index: 0, base_metadata: {})
                                                    .first.metadata[:image_render][:rows]
      expect(rows).to eq(56)
    end

    it 'falls back to the bounded estimate when the page height is unknown' do
      rows = builder(width: 120, max_image_rows: nil).block_lines(block, block_index: 0, base_metadata: {})
                                                     .first.metadata[:image_render][:rows]
      expect(rows).to be_between(4, 18)
    end
  end

  describe 'inline image sizing' do
    it 'keeps inline images modest rather than full-page' do
      rows = builder(width: 120, max_image_rows: 48).inline_lines({ src: 'image0001.jpg', alt: 'a' }, 0)
                                                    .first.metadata[:image_render][:rows]
      expect(rows).to be <= 18
    end
  end
end
