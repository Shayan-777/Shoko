# frozen_string_literal: true

require 'spec_helper'
require 'shoko/application/services/pagination/pagination_layout_resolver'
require 'shoko/adapters/storage/pagination_cache'

RSpec.describe Shoko::Application::Services::Pagination::PaginationLayoutResolver do
  ConfigStub = Struct.new(:view_mode, :line_spacing, :paragraph_style, :justify, keyword_init: true)

  let(:display_capabilities) { double('DisplayCapabilities', kitty_images_enabled?: false) }
  let(:resolver) do
    described_class.new(
      display_capabilities: display_capabilities,
      pagination_cache: Shoko::Adapters::Storage::PaginationCache
    )
  end

  def spec_for(config)
    resolver.resolve(config_reader: config, width: 100, height: 40)
  end

  it 'keeps the :base variant for follow-the-book typography defaults' do
    config = ConfigStub.new(view_mode: :single, line_spacing: :normal, paragraph_style: :book, justify: :book)

    expect(spec_for(config).layout_variant).to eq(:base)
    expect(spec_for(config).cache_key).to end_with('_base')
  end

  it 'treats persisted string config values the same as symbols' do
    # config.json round-trips symbols as strings; the cache key must not
    # change between the in-memory save and the reloaded session, or every
    # warm open repaginates the whole book.
    strings = ConfigStub.new(view_mode: 'single', line_spacing: 'normal',
                             paragraph_style: 'book', justify: 'book')
    symbols = ConfigStub.new(view_mode: :single, line_spacing: :normal,
                             paragraph_style: :book, justify: :book)

    expect(spec_for(strings).layout_variant).to eq(:base)
    expect(spec_for(strings).layout_variant).to eq(spec_for(symbols).layout_variant)
  end

  it 'encodes non-default typography into the layout variant and round-trips it' do
    config = ConfigStub.new(view_mode: :single, line_spacing: :normal,
                            paragraph_style: 'indent', justify: 'on')
    spec = spec_for(config)

    expect(spec.layout_variant).to eq(:"t-indent-on")

    parsed = resolver.from_cache_key(spec.cache_key)
    expect(parsed.layout_variant).to eq(:"t-indent-on")
    expect(resolver.matches_cache_key?(spec.cache_key, parsed)).to be(true)
  end
end
