# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Application workflow guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:app_root) { File.join(root, 'lib', 'shoko', 'application') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids respond_to?(:call) callback introspection in menu workflows' do
    files = Dir[File.join(app_root, 'workflows', 'menu', '**', '*.rb')]
    pattern = /\brespond_to\?\(\s*:call\s*\)/
    offenders = files.select { |path| non_comment_content(path).match?(pattern) }

    expect(offenders).to be_empty,
                         "Menu workflow files still inspect callback callability:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids callback-style reader launch dependencies in application workflow wiring' do
    path = File.join(app_root, 'workflows', 'menu', 'reader_launch_service.rb')
    content = non_comment_content(path)
    forbidden = %w[
      draw_screen:
      switch_mode:
      build_reader_controller:
      selected_book_reader:
      filtered_books_reader:
      progress_presenter_factory:
    ]

    offenders = forbidden.select { |snippet| content.include?(snippet) }
    expect(offenders).to eq([]),
                         "ReaderLaunchService includes callback-style boundary deps: #{offenders.join(', ')}"
  end

  it 'forbids callback-style redraw/scan dependencies in menu workflows' do
    files = Dir[File.join(app_root, 'workflows', 'menu', '**', '*.rb')]
    patterns = {
      'draw_screen keyword dependency' => /\bdraw_screen:\s*/,
      'refresh_scan keyword dependency' => /\brefresh_scan:\s*/,
      'draw_screen callback invocation' => /@draw_screen\.call/,
      'refresh_scan callback invocation' => /@refresh_scan\.call/,
    }

    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |label, pattern|
        next unless content.match?(pattern)

        "#{path}: #{label}"
      end
    end

    expect(offenders).to be_empty,
                         "Menu workflows still include callback-style redraw/scan wiring:\n#{offenders.sort.join("\n")}"
  end

  it 'forbids direct ui_controller coupling in PendingJumpHandler' do
    path = File.join(app_root, 'pending_jump_handler.rb')
    content = non_comment_content(path)
    forbidden = %w[
      ui_controller
      open_annotation_editor_overlay
    ]

    offenders = forbidden.select { |snippet| content.include?(snippet) }
    expect(offenders).to eq([]),
                         "PendingJumpHandler couples directly to UI controller API: #{offenders.join(', ')}"
  end

  it 'forbids frame coordinator coupling in application pagination orchestration' do
    files = [
      File.join(app_root, 'services', 'pagination', 'pagination_orchestrator.rb'),
      File.join(app_root, 'services', 'pagination', 'pagination_coordinator.rb'),
    ]
    offenders = files.select { |path| non_comment_content(path).include?('frame_coordinator') }

    expect(offenders).to be_empty,
                         "Application pagination files still reference frame coordinator:\n#{offenders.join("\n")}"
  end

  it 'forbids application layer dependencies on controller runtime APIs' do
    files = Dir[File.join(app_root, '**', '*.rb')]
    patterns = {
      'controller.state_controller coupling' => /\bcontroller\.state_controller\b/,
      'controller.main_loop coupling' => /\bcontroller\.main_loop\b/,
      'controller metrics mutation coupling' => /\bcontroller\.mark_metrics_start!\b/,
      'controller observer cleanup coupling' => /\bcontroller\.cleanup_observers\b/
    }

    offenders = files.flat_map do |path|
      content = non_comment_content(path)
      patterns.filter_map do |label, pattern|
        next unless content.match?(pattern)

        "#{path}: #{label}"
      end
    end

    expect(offenders).to be_empty,
                         "Application layer still orchestrates controller runtime API directly:\n#{offenders.join("\n")}"
  end

  it 'forbids terminal_service dependencies in application layer' do
    files = Dir[File.join(app_root, '**', '*.rb')]
    offenders = files.select { |path| non_comment_content(path).match?(/\bterminal_service\b/) }

    expect(offenders).to be_empty,
                         "Application layer still depends on terminal_service:\n#{offenders.join("\n")}"
  end
end
