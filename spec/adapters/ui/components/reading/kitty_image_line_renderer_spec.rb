# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Reading::KittyImageLineRenderer do
  FakeKittyRenderer = Class.new do
    def prepare_virtual(**)
      raise StandardError, 'boom'
    end
  end

  FakeDeps = Class.new do
    def initialize(kitty)
      @kitty = kitty
    end

    def kitty_image_renderer
      @kitty
    end
  end

  Line = Struct.new(:metadata)
  Context = Struct.new(:document)

  it 'raises when rendering fails' do
    renderer = described_class.new(dependencies: FakeDeps.new(FakeKittyRenderer.new),
                                   placed_kitty_images: {})
    meta = {
      image_render_line: true,
      image_render: { cols: 10, rows: 4, col_offset: 0 },
      image: { src: 'img.png' },
      chapter_source_path: 'chapter.xhtml',
    }
    line = Line.new(meta)
    expect { renderer.render(line, Context.new(nil)) }.to raise_error(StandardError, 'boom')
  end
end
