# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::State::MenuHitRegistry do
  subject(:registry) { described_class.new }

  it 'resolves clicks against registered regions, topmost (last) first' do
    registry.register(col: 1, row: 1, width: 30, height: 20, action: { type: :rail_surface })
    registry.register(col: 1, row: 5, width: 30, height: 1, action: { type: :rail, index: 0 })

    expect(registry.hit(10, 5)).to eq(type: :rail, index: 0)
    expect(registry.hit(10, 6)).to eq(type: :rail_surface)
    expect(registry.hit(40, 5)).to be_nil
  end

  it 'clears regions at frame start but keeps the pointer position' do
    registry.register(col: 1, row: 1, width: 10, height: 1, action: { type: :rail, index: 0 })
    registry.pointer_moved(5, 1)
    registry.begin_frame!

    expect(registry.hit(5, 1)).to be_nil
    expect(registry.hover?(col: 1, row: 1, width: 10, height: 1)).to be(true)
    expect(registry.hover?(col: 1, row: 2, width: 10, height: 1)).to be(false)
  end

  it 'ignores empty regions and reports no hover before any motion' do
    registry.register(col: 1, row: 1, width: 0, height: 1, action: { type: :rail, index: 0 })

    expect(registry.hit(1, 1)).to be_nil
    expect(registry.hover?(col: 1, row: 1, width: 10, height: 1)).to be(false)
  end
end
