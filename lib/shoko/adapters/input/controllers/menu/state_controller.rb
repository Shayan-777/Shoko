# frozen_string_literal: true

module Shoko
  module Adapters
    module Input
      module Controllers
        module Menu
          # Coordinates menu workflows via precomposed collaborators.
          class StateController
            WorkflowDependencies = Data.define(
              :download_workflow,
              :dictionary_workflow,
              :translator_packs_workflow,
              :translator_workflow,
              :rss_reader_workflow,
              :annotation_workflow
            ) do
              def validate!
                missing = self.class.members.select { |field| public_send(field).nil? }
                return self if missing.empty?

                raise ArgumentError, "Missing required menu workflow dependencies: #{missing.join(', ')}"
              end
            end

            Dependencies = Data.define(
              :reader_launch_service,
              :workflows,
              :catalog
            ) do
              def validate!
                missing = self.class.members.select { |field| public_send(field).nil? }
                unless missing.empty?
                  raise ArgumentError,
                        "Missing required menu state controller dependencies: #{missing.join(', ')}"
                end

                workflows.validate!
                self
              end
            end

            def initialize(deps:)
              raise ArgumentError, 'deps is required' if deps.nil?

              assign_dependencies(deps.validate!)
            end

            def open_selected_book
              @reader_launch_service.open_selected_book
            end

            def open_book(path)
              @reader_launch_service.open_book(path)
            end

            def run_reader(path)
              @reader_launch_service.run_reader(path)
            end

            def load_and_open_with_progress(path)
              @reader_launch_service.load_and_open_with_progress(path)
            end

            def file_not_found
              @reader_launch_service.file_not_found
            end

            def handle_reader_error(path, error)
              @reader_launch_service.handle_reader_error(path, error)
            end

            def valid_cache_path?(path)
              @reader_launch_service.valid_cache_path?(path)
            end

            def refresh_scan(force: false)
              @catalog.start_scan(force: force)
            end

            def search_downloads(query:, page_url: nil)
              @download_workflow.search_downloads(query: query, page_url: page_url)
            end

            def download_book(book)
              @download_workflow.download_book(book)
            end

            def fetch_dictionary_catalog
              @dictionary_workflow.fetch_dictionary_catalog
            end

            def fetch_pack_catalog
              @translator_packs_workflow.fetch_pack_catalog
            end

            def download_pack(entry)
              @translator_packs_workflow.download_pack(entry)
            end

            def download_dictionary(entry)
              @dictionary_workflow.download_dictionary(entry)
            end

            def fetch_translation_languages(force: false)
              @translator_workflow.fetch_languages(force: force)
            end

            def translate_text(text:, source_lang:, target_lang:)
              @translator_workflow.translate_text(text: text, source_lang: source_lang, target_lang: target_lang)
            end

            def open_selected_annotation
              @annotation_workflow.open_selected_annotation
            end

            def open_selected_annotation_for_edit
              @annotation_workflow.open_selected_annotation_for_edit
            end

            def delete_selected_annotation
              @annotation_workflow.delete_selected_annotation
            end

            def save_current_annotation_edit
              @annotation_workflow.save_current_annotation_edit
            end

            def open_rss_reader
              @rss_reader_workflow.open_reader
            end

            def refresh_rss_reader(status: nil, message: nil, preferred_feed_key: nil, preferred_article_id: nil,
                                   reset_content: false)
              @rss_reader_workflow.refresh_view(
                status: status,
                message: message,
                preferred_feed_key: preferred_feed_key,
                preferred_article_id: preferred_article_id,
                reset_content: reset_content
              )
            end

            def sync_rss_feeds
              @rss_reader_workflow.sync_feeds
            end

            def add_rss_feed(url)
              @rss_reader_workflow.add_feed(url)
            end

            def remove_rss_feed(feed_key)
              @rss_reader_workflow.remove_feed(feed_key)
            end

            def set_rss_article_read(article_id, read:)
              @rss_reader_workflow.set_article_read(article_id, read: read)
            end

            def set_rss_article_starred(article_id, starred:)
              @rss_reader_workflow.set_article_starred(article_id, starred: starred)
            end

            private

            def assign_dependencies(dependencies)
              @reader_launch_service = dependencies.reader_launch_service
              @catalog = dependencies.catalog
              assign_workflows(dependencies.workflows)
            end

            def assign_workflows(workflows)
              @download_workflow = workflows.download_workflow
              @dictionary_workflow = workflows.dictionary_workflow
              @translator_packs_workflow = workflows.translator_packs_workflow
              @translator_workflow = workflows.translator_workflow
              @rss_reader_workflow = workflows.rss_reader_workflow
              @annotation_workflow = workflows.annotation_workflow
            end
          end
        end
      end
    end
  end
end
