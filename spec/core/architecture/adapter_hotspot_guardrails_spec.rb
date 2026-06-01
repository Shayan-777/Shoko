# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Adapter hotspot guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }

  # NOTE: the UI component hotspot budgets were removed — they were mood-specs
  # mandating the single-use mixin extraction the architecture constitution outlaws
  # (R1 hard-zero; R2 length-is-not-a-trigger; §V no mood-specs). The sqlite entries
  # remain only until the storage zone inlines those support mixins too.
  def hotspot_budgets
    {
      'lib/shoko/adapters/storage/sqlite_dictionary_adapter.rb' => 180,
      'lib/shoko/adapters/storage/sqlite_dictionary_adapter/database_support.rb' => 110,
      'lib/shoko/adapters/storage/sqlite_dictionary_adapter/fuzzy_query_support.rb' => 340,
      # ARCH-3: ranking/levenshtein extracted from the host into a stateless
      # FuzzyRanker collaborator (was fuzzy_ranking_support.rb + levenshtein_support.rb).
      'lib/shoko/adapters/storage/sqlite_dictionary_adapter/fuzzy_ranker.rb' => 290,
    }
  end

  def responsibility_patterns
    {
      'lib/shoko/adapters/storage/sqlite_dictionary_adapter.rb' => {
        'query builder internals' => /^\s*def translation_candidate_queries\b/,
        'candidate ranking internals' => /^\s*def score_candidates\b/,
        'distance algorithm internals' => /^\s*def levenshtein_distance\b/,
        'backend error classification' => /^\s*def classify_sqlite_failure\b/,
      },
    }
  end

  def rel(path)
    path.delete_prefix("#{root}/")
  end

  def line_count(path)
    File.readlines(path).length
  end

  it 'keeps former monolith hotspots split into focused files' do
    missing = hotspot_budgets.keys.reject { |relative_path| File.exist?(File.join(root, relative_path)) }
    expect(missing).to eq([]), "Expected extracted hotspot files are missing:\n#{missing.join("\n")}"

    offenders = hotspot_budgets.filter_map do |relative_path, max_lines|
      path = File.join(root, relative_path)
      count = line_count(path)
      "#{relative_path} (#{count} > #{max_lines})" if count > max_lines
    end

    expect(offenders).to eq([]),
                         "Adapter hotspot files exceeded their size budget:\n#{offenders.join("\n")}"
  end

  it 'keeps extracted responsibilities out of hotspot entrypoint files' do
    offenders = responsibility_patterns.flat_map do |relative_path, patterns|
      content = File.read(File.join(root, relative_path))
      patterns.filter_map do |label, pattern|
        "#{relative_path}: #{label}" if content.match?(pattern)
      end
    end

    expect(offenders).to eq([]),
                         "Hotspot entrypoint files reabsorbed extracted responsibilities:\n#{offenders.join("\n")}"
  end
end
