# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Services::Pagination::Internal::DynamicLayoutCache do
  subject(:cache) { described_class.new(cache_limit: 3) }

  it 'normalizes cached, activated, and loaded pages to symbol-keyed hashes' do
    cached_pages = [{ 'chapter_index' => 1, 'start_line' => 4 }]
    active_pages = [{ 'chapter_index' => 2, 'start_line' => 8 }]
    loaded_pages = [{ 'chapter_index' => 3, 'start_line' => 12 }]

    cache.cache_pages(key: 'cached', pages: cached_pages)
    activated = cache.activate(key: 'active', pages: active_pages, width: 80, height: 24, sidebar_visible: false)
    cache.load_pages(pages: loaded_pages, key: 'loaded', width: 82, height: 26, sidebar_visible: true)

    expect(cache.cached_pages('cached')).to eq([{ chapter_index: 1, start_line: 4 }])
    expect(activated).to eq([{ chapter_index: 2, start_line: 8 }])
    expect(cache.pages_data).to eq([{ chapter_index: 3, start_line: 12 }])
    expect(cache.cached_pages('loaded')).to eq([{ chapter_index: 3, start_line: 12 }])
  end

  it 'normalizes replacement pages before storing them' do
    cache.activate(
      key: 'active',
      pages: [{ chapter_index: 1, start_line: 2 }],
      width: 80,
      height: 24,
      sidebar_visible: false
    )

    cache.replace_page(0, { 'chapter_index' => 4, 'start_line' => 16 })

    expect(cache.raw_page(0)).to eq({ chapter_index: 4, start_line: 16 })
  end
end
