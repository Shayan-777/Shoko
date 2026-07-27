# frozen_string_literal: true

module Shoko
  module Application
    module State
      module Schema
        # Application-owned menu transient-state schema fragment.
        #
        # Owns the non-persisted slice of `state[:menu]`: workflow results
        # (download/dictionary/translator/RSS payloads), live status, progress,
        # and loading mirrors. These are produced by application workflows in
        # response to user intents and are discarded on restart.
        module MenuTransient
          PARTITION = :menu

          FIELDS = %i[
            download_results
            download_count
            download_next
            download_prev
            download_status
            download_message
            download_progress
            dictionary_results
            dictionary_status
            dictionary_message
            dictionary_progress
            translator_output_text
            translator_detected_source_lang
            translator_languages
            translator_status
            translator_message
            translator_selection
            translator_context_menu
            translator_packs_results
            translator_packs_status
            translator_packs_message
            translator_packs_progress
            rss_feeds
            rss_articles
            rss_open_article
            rss_status
            rss_message
            rss_last_synced_at
            rss_selection
            rss_context_menu
            rss_find_active
            rss_find_index
            rss_lookup_query
            rss_lookup_result
            rss_lookup_status
            rss_lookup_message
            rss_annotations
            annotations_all
            loading_active
            loading_progress
            loading_message
            prepaginate_active
            prepaginate_done
            prepaginate_total
            prepaginate_paths
            startup_notice
          ].freeze

          DEFAULTS = {
            download_results: [].freeze,
            download_count: 0,
            download_next: nil,
            download_prev: nil,
            download_status: :idle,
            download_message: '',
            download_progress: 0.0,
            dictionary_results: [].freeze,
            dictionary_status: :idle,
            dictionary_message: '',
            dictionary_progress: 0.0,
            translator_output_text: '',
            translator_detected_source_lang: nil,
            translator_languages: [].freeze,
            translator_status: :idle,
            translator_message: 'Type text to translate.',
            translator_selection: nil,
            translator_context_menu: nil,
            translator_packs_results: [].freeze,
            translator_packs_status: :idle,
            translator_packs_message: '',
            translator_packs_progress: 0.0,
            rss_feeds: [].freeze,
            rss_articles: [].freeze,
            rss_open_article: nil,
            rss_status: :empty,
            rss_message: 'Press A to add a feed URL',
            rss_last_synced_at: nil,
            # Live reading-pane interaction: the current text selection, the
            # right-click menu over it, and the in-article find.
            rss_selection: nil,
            rss_context_menu: nil,
            rss_find_active: false,
            rss_find_index: 0,
            rss_lookup_query: '',
            rss_lookup_result: nil,
            rss_lookup_status: :idle,
            rss_lookup_message: '',
            rss_annotations: [].freeze,
            annotations_all: {}.freeze,
            loading_active: false,
            loading_progress: nil,
            loading_message: nil,
            prepaginate_active: false,
            prepaginate_done: 0,
            prepaginate_total: 0,
            prepaginate_paths: [].freeze,
            startup_notice: nil,
          }.freeze

          module_function

          def contribute(_context = {})
            { PARTITION => DEFAULTS.slice(*FIELDS) }
          end
        end
      end
    end
  end
end
