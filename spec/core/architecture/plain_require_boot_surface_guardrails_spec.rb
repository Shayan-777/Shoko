# frozen_string_literal: true

require 'json'
require 'open3'
require 'spec_helper'

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
      shoko/composition/container_factory/controller_composition/reader_builder.rb
      shoko/composition/container_factory/controller_composition/reader_runtime_assembler.rb
      shoko/adapters/input/controllers/annotation_overlay_controller.rb
      shoko/adapters/input/controllers/dictionary_controller.rb
      shoko/adapters/input/controllers/in_book_search_controller.rb
      shoko/adapters/input/controllers/sidebar_controller.rb
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
      shoko/adapters/book_sources/document_loader_adapter.rb
      shoko/adapters/book_sources/cache_import_adapter.rb
      shoko/application/workflows/cli/folder_import_workflow.rb
      shoko/application/workflows/cli/folder_import_readiness_warmup.rb
    ].freeze

    loaded_forbidden = features.select do |feature|
      forbidden_suffixes.any? { |suffix| feature.end_with?(suffix) }
    end

    expect(loaded_forbidden).to eq([])
  end
end
