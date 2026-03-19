# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Adapter hotspot guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  HOTSPOT_BUDGETS = {
    'lib/shoko/adapters/ui/components/annotation_editor_overlay_component.rb' => 320,
    'lib/shoko/adapters/ui/components/annotation_editor_overlay/render_support.rb' => 340,
    'lib/shoko/adapters/ui/components/annotation_editor_overlay/spell_support.rb' => 320,
    'lib/shoko/adapters/ui/components/in_book_search_popup_component.rb' => 260,
    'lib/shoko/adapters/ui/components/in_book_search_popup/render_support.rb' => 380,
    'lib/shoko/adapters/ui/components/in_book_search_popup/result_support.rb' => 130,
    'lib/shoko/adapters/ui/components/ui/backdrop_overlay.rb' => 150,
    'lib/shoko/adapters/storage/sqlite_dictionary_adapter.rb' => 180,
    'lib/shoko/adapters/storage/sqlite_dictionary_adapter/database_support.rb' => 110,
    'lib/shoko/adapters/storage/sqlite_dictionary_adapter/fuzzy_query_support.rb' => 340,
    'lib/shoko/adapters/storage/sqlite_dictionary_adapter/fuzzy_ranking_support.rb' => 240,
  }.freeze

  RESPONSIBILITY_PATTERNS = {
    'lib/shoko/adapters/ui/components/annotation_editor_overlay_component.rb' => {
      'spell popup rendering' => /^\s*def render_spell_suggestion_popup\b/,
      'spell popup state normalization' => /^\s*def normalize_spell_target\b/,
      'backdrop geometry merging' => /^\s*def merge_geometry_cells\b/,
      'note render-state construction' => /^\s*def note_render_state\b/,
    },
    'lib/shoko/adapters/ui/components/in_book_search_popup_component.rb' => {
      'result normalization' => /^\s*def normalize_results\b/,
      'result-card rendering' => /^\s*def render_result_card\b/,
      'backdrop geometry merging' => /^\s*def merge_geometry_cells\b/,
      'text layout helpers' => /^\s*def align_left_right\b/,
    },
    'lib/shoko/adapters/storage/sqlite_dictionary_adapter.rb' => {
      'query builder internals' => /^\s*def translation_candidate_queries\b/,
      'candidate ranking internals' => /^\s*def score_candidates\b/,
      'distance algorithm internals' => /^\s*def levenshtein_distance\b/,
      'backend error classification' => /^\s*def classify_sqlite_failure\b/,
    },
  }.freeze

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  def line_count(path)
    File.readlines(path).length
  end

  it 'keeps former monolith hotspots split into focused files' do
    missing = HOTSPOT_BUDGETS.keys.reject { |relative_path| File.exist?(File.join(root, relative_path)) }
    expect(missing).to eq([]), "Expected extracted hotspot files are missing:\n#{missing.join("\n")}"

    offenders = HOTSPOT_BUDGETS.filter_map do |relative_path, max_lines|
      path = File.join(root, relative_path)
      count = line_count(path)
      "#{relative_path} (#{count} > #{max_lines})" if count > max_lines
    end

    expect(offenders).to eq([]),
                         "Adapter hotspot files exceeded their size budget:\n#{offenders.join("\n")}"
  end

  it 'keeps extracted responsibilities out of hotspot entrypoint files' do
    offenders = RESPONSIBILITY_PATTERNS.flat_map do |relative_path, patterns|
      content = File.read(File.join(root, relative_path))
      patterns.filter_map do |label, pattern|
        "#{relative_path}: #{label}" if content.match?(pattern)
      end
    end

    expect(offenders).to eq([]),
                         "Hotspot entrypoint files reabsorbed extracted responsibilities:\n#{offenders.join("\n")}"
  end
end
