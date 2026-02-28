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
    [:dark, 80, 24],
    [:light, 80, 24],
    [:dark, 120, 40],
    [:light, 120, 40]
  ].each do |mode, width, height|
    it "renders coherent annotation detail layout in #{mode} mode at #{width}x#{height}" do
      writes = with_color_mode(mode) { render_component(component, width: width, height: height) }
      text = rendered_text(writes)

      expect(text).to include('Annotation Detail')
      expect(text).to include('Selected Text')
      expect(text).to include('Note')
      expect(text).to include('Book •')
      expect(writes.any? { |entry| entry[:row] == 2 && strip_ansi(entry[:text]).include?('─') }).to be(true)
    end
  end
end
