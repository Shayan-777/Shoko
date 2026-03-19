# frozen_string_literal: true

require 'open3'
require 'spec_helper'

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
      shoko/adapters/ui/rendering/line/config_helpers
      shoko/application/services/reader/navigation/absolute_layout
      shoko/application/services/pagination/page_calculator_service
      shoko/application/services/pagination/page_info_calculator
      shoko/application/services/pagination/internal/layout_metrics_calculator
      shoko/application/services/pagination/internal/pagination_workflow
      shoko/adapters/input/controllers/state_controller/bookmark_actions
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
