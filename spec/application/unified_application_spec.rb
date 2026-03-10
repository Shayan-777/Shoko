# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::UnifiedApplication do
  let(:epub_path) { '/books/example.epub' }
  let(:app_mode_runner) { instance_double('AppModeRunner', run_reader: nil, run_menu: nil) }
  let(:deps) do
    described_class::Dependencies.new(
      app_mode_runner: app_mode_runner
    )
  end

  it 'dispatches reader mode through the runtime runner boundary' do
    expect(app_mode_runner).to receive(:run_reader).with(path: epub_path).ordered

    described_class.new(epub_path, deps: deps).run
  end

  it 'dispatches menu mode through the runtime runner boundary' do
    app = described_class.new(nil, deps: deps)

    expect(app_mode_runner).to receive(:run_menu)

    app.run
  end
end
