# frozen_string_literal: true

require 'json'
require 'open3'
require 'spec_helper'

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
      'sidebar_controller' => 'constant',
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
        sidebar_controller: defined?(Shoko::Adapters::Input::Controllers::SidebarController),
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
