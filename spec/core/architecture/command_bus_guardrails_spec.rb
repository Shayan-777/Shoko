# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Intent boundary guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids controller includes of inbound ports' do
    controller_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '**', '*.rb')]
    offenders = controller_files.select do |path|
      content = non_comment_content(path)
      content.include?('include Shoko::Application::Ports::Inbound::')
    end

    expect(offenders).to eq([]),
                         "Controllers still include inbound ports:\n#{offenders.join("\n")}"
  end

  it 'forbids hybrid reader and menu intent symbols from reappearing' do
    forbidden = %w[
      read_scroll_down_or_sidebar
      read_scroll_up_or_sidebar
      read_confirm_or_sidebar
      read_space_or_sidebar_toggle
      help_exit_to_read
      dictionary_insert_char_if_printable
      in_book_search_insert_char_if_printable
      annotation_editor_insert_char_if_printable
      search_insert_char
      dictionary_search_insert_char
      download_search_insert_char
      annotation_editor_insert_char
      annotation_editor_enter
    ]

    files = [
      File.join(lib_root, 'adapters', 'input', 'dispatcher.rb'),
      File.join(lib_root, 'adapters', 'input', 'reader_input_controller.rb'),
      File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'input_controller.rb'),
      *Dir[File.join(lib_root, 'application', 'use_cases', '**', '*.rb')],
      *Dir[File.join(lib_root, 'core', 'ports', 'inbound', '*.rb')],
    ]
    offenders = files.select do |path|
      content = non_comment_content(path)
      forbidden.any? { |term| content.include?(term) }
    end

    expect(offenders).to eq([]),
                         "Hybrid or legacy intent symbols remain:\n#{offenders.join("\n")}"
  end
end
