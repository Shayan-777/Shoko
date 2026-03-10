# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Controller composition boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:files) { Dir[File.join(lib_root, '**', '*.rb')] }
  let(:allowed_paths) do
    [
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_builder.rb'),
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_runtime_assembler.rb'),
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'menu_state_controller_composer.rb')
    ].freeze
  end
  let(:allowed_prefixes) do
    [
      "#{File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_runtime_assembler')}/"
    ].freeze
  end
  let(:controller_names) do
    %w[
      UIController
      StateController
      SidebarController
      DictionaryController
      AnnotationOverlayController
      InBookSearchController
    ].freeze
  end

  it 'allows reader controller graph construction only in composition composition' do
    offenders = []

    files.each do |path|
      next if allowed_paths.include?(path) || allowed_prefixes.any? { |prefix| path.start_with?(prefix) }

      File.readlines(path).each_with_index do |line, index|
        content = line.sub(/\s+#.*\z/, '')

        controller_names.each do |name|
          qualified = /\b(?:Shoko::)?Adapters::Input::Controllers::#{name}\.new\b/
          short = /\b#{name}\.new\b/

          next unless content.match?(qualified) || content.match?(short)
          next if name == 'StateController' && content.match?(/\b(?:Shoko::)?Adapters::Input::Controllers::Menu::StateController\.new\b/)
          next if name == 'StateController' && content.match?(/\bMenu::StateController\.new\b/)

          offenders << "#{path}:#{index + 1} #{name}.new"
        end
      end
    end

    expect(offenders).to eq([]),
                         "Controller graph composition escaped composition reader_builder:\n#{offenders.sort.join("\n")}"
  end

  it 'keeps controller composition files within the phase-4 size budget' do
    controller_composition_files = Dir[
      File.join(lib_root, 'composition', 'container_factory', 'controller_composition', '**', '*.rb')
    ]

    offenders = controller_composition_files.filter_map do |path|
      line_count = File.readlines(path).length
      next unless line_count > 200

      "#{path}: #{line_count}"
    end

    expect(offenders).to eq([]),
                         "Controller composition files exceed 200 lines:\n#{offenders.sort.join("\n")}"
  end

  it 'keeps concrete input controller entrypoints within the phase-4 size budget' do
    controller_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', '*_controller.rb')] +
                       [
                         File.join(lib_root, 'adapters', 'input', 'controllers', 'mouseable_reader.rb'),
                         File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'controller.rb'),
                         File.join(lib_root, 'adapters', 'input', 'controllers', 'menu', 'input_controller.rb')
                       ]

    offenders = controller_files.uniq.sort.filter_map do |path|
      line_count = File.readlines(path).length
      next unless line_count > 300

      "#{path}: #{line_count}"
    end

    expect(offenders).to eq([]),
                         "Controller entrypoint files exceed 300 lines:\n#{offenders.join("\n")}"
  end

  it 'keeps extracted ui delegation and inline-link helper files within the phase-4 size budget' do
    helper_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'ui_controller', '**', '*.rb')] +
                   Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'inline_link', '**', '*.rb')] +
                   [File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'inline_link_navigator.rb')]

    offenders = helper_files.uniq.sort.filter_map do |path|
      line_count = File.readlines(path).length
      next unless line_count > 200

      "#{path}: #{line_count}"
    end

    expect(offenders).to eq([]),
                         "Extracted ui/inline-link helper files exceed 200 lines:\n#{offenders.join("\n")}"
  end

  it 'keeps extracted mouse/sidebar/runtime bridge helper files within the phase-4 size budget' do
    helper_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'selection_mouse_handler', '**', '*.rb')] +
                   Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'sidebar_mouse_handler', '**', '*.rb')] +
                   Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'intent_runtime_bridge', '**', '*.rb')] +
                   Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'sidebar', 'selection_coordinator', '**', '*.rb')] +
                   [
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'selection_mouse_handler.rb'),
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'sidebar_mouse_handler.rb'),
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'intent_runtime_bridge.rb'),
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'sidebar', 'selection_coordinator.rb')
                   ]

    offenders = helper_files.uniq.sort.filter_map do |path|
      line_count = File.readlines(path).length
      next unless line_count > 200

      "#{path}: #{line_count}"
    end

    expect(offenders).to eq([]),
                         "Extracted mouse/sidebar/runtime bridge helper files exceed 200 lines:\n#{offenders.join("\n")}"
  end

  it 'keeps extracted search and spellcheck helper files within the phase-4 size budget' do
    helper_files = Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'in_book_search', 'result_navigator', '**', '*.rb')] +
                   Dir[File.join(lib_root, 'adapters', 'input', 'controllers', 'annotation_overlay', 'spellcheck_coordinator', '**', '*.rb')] +
                   [
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'in_book_search', 'result_navigator.rb'),
                     File.join(lib_root, 'adapters', 'input', 'controllers', 'annotation_overlay', 'spellcheck_coordinator.rb')
                   ]

    offenders = helper_files.uniq.sort.filter_map do |path|
      line_count = File.readlines(path).length
      next unless line_count > 200

      "#{path}: #{line_count}"
    end

    expect(offenders).to eq([]),
                         "Extracted search/spellcheck helper files exceed 200 lines:\n#{offenders.join("\n")}"
  end
end
