# frozen_string_literal: true

require 'spec_helper'

# NOTE: this spec previously also enforced "phase-4 size budgets" (controller and
# extracted-helper files <= 200/300 lines). Those examples were removed: they were
# mood-specs that mandated the single-use mixin extraction the architecture
# constitution now outlaws (R1 hard-zero; R2 "length is never a reason to split";
# §V "specs named for moods are forbidden"). The real invariant below — that the
# reader controller graph is wired only in the composition root — is kept.
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
      "#{File.join(lib_root, 'composition', 'container_factory', 'controller_composition', 'reader_builder')}/",
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
end
