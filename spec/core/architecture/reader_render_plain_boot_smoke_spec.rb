# frozen_string_literal: true

require 'json'
require 'open3'
require 'spec_helper'

RSpec.describe 'Reader render plain-boot smoke' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end

  it 'builds view renderers and draws a highlighted display line without eager boot' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), stderr
    expect(JSON.parse(stdout)).to eq(
      'single_renderer' => 'Shoko::Adapters::Ui::Components::Reading::SingleViewRenderer',
      'split_renderer' => 'Shoko::Adapters::Ui::Components::Reading::SplitViewRenderer',
      'geometry_entries' => 1,
      'writes' => 1,
      'highlighting_defined' => 'constant'
    )
  end

  def code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'json'
      require 'shoko'
      require 'shoko/adapters/ui/components/content_component'
      require 'shoko/adapters/ui/components/surface'
      require 'shoko/adapters/ui/components/rect'
      require 'shoko/adapters/ui/rendering/line/line_drawer'

      container = Shoko::Composition::ContainerFactory.create_default_container
      runtime_config = container.resolve(:runtime_config)

      observer_registry = Object.new
      def observer_registry.add_observer(*) = nil

      reader_state = Struct.new(:mode, :hovered_inline_link).new(:read, nil)
      single_config = Struct.new(:view_mode, :page_numbering_mode).new(:single, :dynamic)
      split_config = Struct.new(:view_mode, :page_numbering_mode).new(:split, :dynamic)

      renderer_deps_class = Struct.new(
        :layout_service,
        :layout_metrics,
        :render_state_writer,
        :config_reader,
        :reader_state_reader,
        :rendered_content_reader,
        :logger,
        :observer_registry,
        :reader_launch_state,
        :document,
        :page_calculator,
        :formatting_service,
        :wrapping_service,
        :kitty_image_renderer,
        :runtime_config
      )

      base_renderer_args = [nil, nil, nil, nil, reader_state, nil, nil, observer_registry, nil, nil, nil, nil, nil, nil, runtime_config]
      single_deps = renderer_deps_class.new(*base_renderer_args).tap { |deps| deps.config_reader = single_config }
      split_deps = renderer_deps_class.new(*base_renderer_args).tap { |deps| deps.config_reader = split_config }

      single_renderer = Shoko::Adapters::Ui::Components::Reading::ViewRendererFactory.create(single_deps)
      split_renderer = Shoko::Adapters::Ui::Components::Reading::ViewRendererFactory.create(split_deps)

      terminal_output = Object.new
      writes = []
      terminal_output.define_singleton_method(:write) do |row, col, text|
        writes << [row, col, text]
      end

      config = Struct.new(:highlight_quotes, :highlight_keywords, :line_spacing, :kitty_images).new(true, false, :normal, false)
      line_deps = Struct.new(:runtime_config, :config_reader, :logger).new(runtime_config, config, nil)
      rendered_lines = {}
      drawer = Shoko::Adapters::Ui::Components::Reading::LineDrawer.new(
        dependencies: line_deps,
        rendered_lines_buffer: rendered_lines,
        placed_kitty_images: {},
        record_geometry: true
      )
      surface = Shoko::Adapters::Ui::Components::Surface.new(terminal_output)
      bounds = Shoko::Adapters::Ui::Components::Rect.new(1, 1, 80, 24)
      context = Struct.new(:config_reader, :reader_state_reader, :document).new(config, reader_state, nil)
      line = Shoko::Core::Models::DisplayLine.new(
        text: '"hello"',
        segments: [Shoko::Core::Models::TextSegment.new(text: '"hello"', styles: {})],
        metadata: {}
      )

      drawer.draw_line(
        surface: surface,
        bounds: bounds,
        line: line,
        row: 1,
        col: 1,
        width: 20,
        context: context,
        column_id: 0,
        line_offset: 0,
        page_id: 0
      )

      puts JSON.dump(
        single_renderer: single_renderer.class.name,
        split_renderer: split_renderer.class.name,
        geometry_entries: rendered_lines.length,
        writes: writes.length,
        highlighting_defined: defined?(Shoko::Adapters::Ui::Constants::Highlighting)
      )
    RUBY
  end
end
