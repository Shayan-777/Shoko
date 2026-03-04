# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Controller composition boundaries' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }
  let(:files) { Dir[File.join(lib_root, '**', '*.rb')] }
  let(:allowed_paths) do
    [
      File.join(lib_root, 'bootstrap', 'container_factory', 'controller_composition', 'reader_builder.rb'),
      File.join(lib_root, 'bootstrap', 'container_factory', 'controller_composition', 'reader_runtime_assembler.rb'),
      File.join(lib_root, 'bootstrap', 'container_factory', 'controller_composition', 'menu_state_controller_composer.rb')
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

  it 'allows reader controller graph construction only in bootstrap composition' do
    offenders = []

    files.each do |path|
      next if allowed_paths.include?(path)

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
                         "Controller graph composition escaped bootstrap reader_builder:\n#{offenders.sort.join("\n")}"
  end
end
