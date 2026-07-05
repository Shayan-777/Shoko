# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Ui::Components::Screens::AnnotationDetailScreenComponent do
  include MenuScreenRenderHelpers

  let(:menu_state_reader) do
    instance_double(
      'MenuStateReader',
      selected_annotation: {
        'id' => 'a1',
        'text' => 'Selected quote',
        'note' => 'My note',
        'chapter_index' => 3,
        'created_at' => '2025-01-01T10:20:30Z',
        'page_current' => 12,
        'page_total' => 240,
        'page_mode' => 'dynamic'
      },
      selected_annotation_book: '/tmp/book.epub'
    )
  end
  let(:dependencies) { instance_double('Dependencies', menu_state_reader: menu_state_reader) }
  let(:component) { described_class.new(dependencies: dependencies) }

  [
    [80, 24],
    [120, 40]
  ].each do |width, height|
    it "renders the canvas annotation detail at #{width}x#{height}" do
      writes = render_component(component, width: width, height: height)
      text = rendered_text(writes)

      expect(text).to include('Annotation')
      expect(text).to include('SELECTED TEXT')
      expect(text).to include('NOTE')
      expect(text).not_to include('│')
    end
  end
end
