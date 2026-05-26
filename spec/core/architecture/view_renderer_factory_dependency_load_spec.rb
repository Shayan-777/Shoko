# frozen_string_literal: true

require 'json'
require 'open3'
require 'spec_helper'

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
