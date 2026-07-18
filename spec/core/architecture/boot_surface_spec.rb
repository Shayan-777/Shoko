# frozen_string_literal: true

# Consolidated boot-surface rules (constitution §V): every runtime file
# requires its own dependencies, the plain require surface stays lazy, and
# deferred reader subsystems load without eager boot. Absorbs the former
# isolated_require, plain_require_boot_surface, *_dependency_load and
# reader_render_plain_boot_smoke suites.

require 'json'
require 'open3'
require 'spec_helper'



RSpec.describe 'Isolated require guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:script) { File.join(root, 'script', 'architecture', 'isolated_require_report.rb') }

  it 'requires every runtime file in isolation without relying on manifest order' do
    stdout, stderr, status = Open3.capture3('ruby', script)
    expect(status.success?).to be(true), stderr

    failures = JSON.parse(stdout)
    formatted = failures.map do |failure|
      header = failure.fetch('path')
      details = failure.fetch('stderr').to_s.lines.first(3).join
      "#{header}\n#{details}"
    end
    message = "Runtime files must declare their own dependencies:\n#{formatted.join("\n---\n")}"

    expect(formatted).to eq([]), message
  end
end



RSpec.describe 'Plain require boot surface guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:code) do
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'json'
      require 'shoko'
      puts JSON.dump($LOADED_FEATURES.grep(%r{/lib/shoko/}).sort)
    RUBY
  end

  it 'does not load reader-only composition, reader UI, or deferred reader/cli adapters' do
    env = {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)
    expect(status.success?).to be(true), stderr

    features = JSON.parse(stdout)
    forbidden_suffixes = %w[
      shoko/composition/container_factory.rb
      shoko/composition/container_factory/controller_composition/reader_builder.rb
      shoko/composition/container_factory/controller_composition/reader_runtime_assembler.rb
      shoko/adapters/input/controllers/annotation_overlay_controller.rb
      shoko/adapters/input/controllers/dictionary_controller.rb
      shoko/adapters/input/controllers/in_book_search_controller.rb
      shoko/adapters/input/controllers/ui_controller.rb
      shoko/adapters/ui/rendering/reader_render_coordinator.rb
      shoko/adapters/ui/components/dictionary_panel_component.rb
      shoko/adapters/ui/components/dictionary_popup_component.rb
      shoko/adapters/ui/components/in_book_search_popup_component.rb
      shoko/adapters/ui/components/annotations_overlay_component.rb
      shoko/adapters/ui/components/annotation_editor_overlay_component.rb
      shoko/adapters/ui/components/enhanced_popup_menu.rb
      shoko/adapters/runtime/reader_mode_runner.rb
      shoko/adapters/runtime/app_mode_runner_adapter.rb
      shoko/adapters/runtime/cli_progress_presenter.rb
      shoko/adapters/book_sources/cache_import_adapter.rb
      shoko/application/workflows/cli/folder_import_workflow.rb
      shoko/application/workflows/cli/folder_import_readiness_warmup.rb
    ].freeze

    loaded_forbidden = features.select do |feature|
      forbidden_suffixes.any? { |suffix| feature.end_with?(suffix) }
    end

    expect(loaded_forbidden).to eq([])
  end

  # Not just a denylist: the plain require surface has a total budget. The
  # composition graph autoloads on first reference (constitution §V,
  # amendment 2026-07-18), so `require 'shoko'` must stay a thin CLI
  # surface — version, errors, the CLI adapter, and their direct
  # dependencies. Re-eagering the container factory would blow this budget
  # by an order of magnitude, not sneak past a list.
  it 'keeps the plain require surface within the boot budget' do
    env = {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)
    expect(status.success?).to be(true), stderr

    features = JSON.parse(stdout)
    budget = 10

    expect(features.length).to be <= budget, <<~MSG
      Plain `require 'shoko'` loaded #{features.length} lib/shoko files (budget: #{budget}):
      #{features.join("\n")}
    MSG
  end
end



RSpec.describe 'Reader builder dependency loading' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end

  it 'loads the concrete reader controller classes needed by the lazy reader-builder path' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), stderr

    constants = JSON.parse(stdout)
    expect(constants).to eq(
      'mouseable_reader' => 'constant',
      'ui_controller' => 'constant',
      'state_controller' => 'constant',
      'dictionary_controller' => 'constant',
      'annotation_overlay_controller' => 'constant',
      'in_book_search_controller' => 'constant',
      'reader_lifecycle_runner' => 'constant',
      'reader_intent_runtime_bridge' => 'constant',
      'reader_render_requester_bridge' => 'constant'
    )
  end

  def code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'json'
      require 'shoko'
      require 'shoko/composition/container_factory/controller_composition/reader_builder'
      puts JSON.dump(
        mouseable_reader: defined?(Shoko::Adapters::Input::Controllers::MouseableReader),
        ui_controller: defined?(Shoko::Adapters::Input::Controllers::UIController),
        state_controller: defined?(Shoko::Adapters::Input::Controllers::StateController),
        dictionary_controller: defined?(Shoko::Adapters::Input::Controllers::DictionaryController),
        annotation_overlay_controller: defined?(Shoko::Adapters::Input::Controllers::AnnotationOverlayController),
        in_book_search_controller: defined?(Shoko::Adapters::Input::Controllers::InBookSearchController),
        reader_lifecycle_runner: defined?(Shoko::Adapters::Input::Controllers::Reader::LifecycleRunner),
        reader_intent_runtime_bridge: defined?(Shoko::Adapters::Input::Controllers::Reader::IntentRuntimeBridge),
        reader_render_requester_bridge: defined?(Shoko::Adapters::Input::Controllers::Reader::RenderRequesterBridge)
      )
    RUBY
  end
end



RSpec.describe 'Reader settings dependency loading' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end
  let(:features) do
    %w[
      shoko/application/services/layout_service
      shoko/application/use_cases/settings_service
      shoko/adapters/ui/view_models/reader_view_model_builder
      shoko/application/services/reader/bookmark_service
      shoko/adapters/ui/rendering/line/config_resolution
      shoko/application/services/reader/navigation/absolute_layout
      shoko/application/services/pagination/page_calculator_service
      shoko/application/services/pagination/page_info_calculator
      shoko/application/services/pagination/internal/layout_metrics_calculator
      shoko/application/services/pagination/internal/pagination_workflow
      shoko/adapters/input/controllers/state_controller
    ].freeze
  end

  it 'lets deferred reader services load ReaderSettings without eager boot' do
    failures = features.filter_map do |feature|
      stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', ruby_code(feature))
      next if status.success? && stdout.strip == '"constant"'

      { feature: feature, stdout: stdout.strip, stderr: stderr.strip, status: status.exitstatus }
    end

    expect(failures).to eq([])
  end

  it 'keeps layout service usable on the deferred reader-launch path' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', layout_service_code)

    expect(status.success?).to be(true), stderr
    expect(stdout.lines.map(&:strip)).to eq(%w[constant 90])
  end

  def ruby_code(feature)
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      require #{feature.dump}
      puts defined?(Shoko::Core::Models::ReaderSettings).inspect
    RUBY
  end

  def layout_service_code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      require 'shoko/application/services/layout_service'
      puts defined?(Shoko::Core::Models::ReaderSettings)
      puts Shoko::Application::Services::LayoutService.new.single_column_width(100)
    RUBY
  end
end



RSpec.describe 'View renderer factory dependency loading' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end

  it 'builds both single and split view renderers without eager boot' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), stderr
    expect(JSON.parse(stdout)).to eq(
      'single_renderer_class' => 'Shoko::Adapters::Ui::Components::Reading::SingleViewRenderer',
      'split_renderer_class' => 'Shoko::Adapters::Ui::Components::Reading::SplitViewRenderer',
      'single_defined' => 'constant',
      'split_defined' => 'constant'
    )
  end

  def code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'json'
      require 'shoko'
      require 'shoko/adapters/ui/components/content_component'

      observer_registry = Object.new
      def observer_registry.add_observer(*) = nil

      reader_state = Struct.new(:mode).new(:read)
      single_config = Struct.new(:view_mode, :page_numbering_mode).new(:single, :dynamic)
      split_config = Struct.new(:view_mode, :page_numbering_mode).new(:split, :dynamic)
      deps_class = Struct.new(
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

      runtime_config = Object.new
      def runtime_config.is_a?(klass)
        klass.name == 'Shoko::Application::Ports::Outbound::RuntimeConfig' || super
      end

      base_args = [
        nil,
        nil,
        nil,
        nil,
        reader_state,
        nil,
        nil,
        observer_registry,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        runtime_config
      ]

      single_deps = deps_class.new(*base_args).tap { |deps| deps.config_reader = single_config }
      split_deps = deps_class.new(*base_args).tap { |deps| deps.config_reader = split_config }

      single_renderer = Shoko::Adapters::Ui::Components::Reading::ViewRendererFactory.create(single_deps)
      split_renderer = Shoko::Adapters::Ui::Components::Reading::ViewRendererFactory.create(split_deps)

      puts JSON.dump(
        single_renderer_class: single_renderer.class.name,
        split_renderer_class: split_renderer.class.name,
        single_defined: defined?(Shoko::Adapters::Ui::Components::Reading::SingleViewRenderer),
        split_defined: defined?(Shoko::Adapters::Ui::Components::Reading::SplitViewRenderer)
      )
    RUBY
  end
end



RSpec.describe 'XHTML parser factory dependency loading' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:env) do
    {
      'SHOKO_TEST_MODE' => nil,
      'SHOKO_EAGER_BOOT' => nil,
    }
  end

  it 'builds the deferred xhtml parser factory without eager boot' do
    stdout, stderr, status = Open3.capture3(env, 'ruby', '-e', code)

    expect(status.success?).to be(true), stderr
    expect(stdout.lines.map(&:strip)).to eq(
      [
        'Shoko::Adapters::BookSources::Epub::XHTMLContentParser',
        'constant',
      ]
    )
  end

  def code
    <<~RUBY
      $LOAD_PATH.unshift File.expand_path('lib', #{root.dump})
      require 'shoko'
      container = Shoko::Composition::ContainerFactory.create_default_container
      parser = container.resolve(:xhtml_parser_factory).call('<html><body><p>hello</p></body></html>')
      puts parser.class.name
      puts defined?(Shoko::Adapters::BookSources::Epub::XHTMLContentParser)
    RUBY
  end
end



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
      line = Shoko::Application::Ports::Outbound::Formatting::DisplayLine.new(
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
