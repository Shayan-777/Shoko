# frozen_string_literal: true

require_relative '../../use_cases/support/menu_session_access'
require_relative '../../services/async_result_relay'

module Shoko
  module Application
    module Workflows
      module Menu
        # Coordinates menu-side RSS reader state against the local RSS service.
        #
        # Feed syncing and adding run through an AsyncResultRelay so fetching
        # N feeds over the network cannot freeze the menu; snapshots are
        # applied on the menu thread when the relay drains. Without a relay
        # executor the workflow stays fully synchronous.
        class RssReaderWorkflow
          include Shoko::Application::UseCases::Support::MenuSessionAccess

          ALL_FEEDS_KEY = '__all__'

          def initialize(rss_reader_service:, menu_session_store:, menu_transient_store:, async_relay: nil,
                         logger: nil)
            raise ArgumentError, 'rss_reader_service is required' if rss_reader_service.nil?

            assign_menu_session_store!(menu_session_store, menu_transient_store: menu_transient_store)
            @rss_reader_service = rss_reader_service
            @async_relay = async_relay || Shoko::Application::Services::AsyncResultRelay.new(logger: logger)
            @logger = logger
          end

          # Applies any results the worker produced; called from the menu loop
          # on the UI thread.
          def process_pending_events
            @async_relay.drain!
          end

          def network_pending?
            @async_relay.busy?
          end

          def open_reader
            refresh_view(status: default_status, message: nil)
          end

          def refresh_view(status: nil, message: nil, preferred_feed_key: nil, preferred_article_id: nil,
                           reset_content: false)
            apply_snapshot(
              @rss_reader_service.snapshot,
              status: status || default_status,
              message: message,
              preferred_feed_key: preferred_feed_key,
              preferred_article_id: preferred_article_id,
              reset_content: reset_content
            )
          rescue Shoko::Error => e
            log_error('rss_reader.refresh_view_failed', e)
            update_menu(rss_status: :error, rss_message: e.message)
          end

          def sync_feeds
            update_menu(rss_status: :syncing, rss_message: 'Syncing feeds...')
            @async_relay.submit { perform_feed_sync }
          end

          def add_feed(url)
            update_menu(rss_status: :syncing, rss_message: 'Adding feed...')
            @async_relay.submit { perform_feed_add(url) }
          end

          # Worker-side network jobs: compute only, results applied via relay.
          def perform_feed_sync
            result = @rss_reader_service.sync_all
            @async_relay.enqueue do
              apply_snapshot(
                result[:snapshot],
                status: result[:errors].empty? ? :ready : :error,
                message: sync_message(result),
                reset_content: true
              )
            end
          rescue Shoko::Error => e
            @async_relay.enqueue do
              log_error('rss_reader.sync_feeds_failed', e)
              update_menu(rss_status: :error, rss_message: e.message)
            end
          end
          private :perform_feed_sync

          def perform_feed_add(url)
            result = @rss_reader_service.add_feed(url)
            message = "Added #{result[:added_count]} #{article_word(result[:added_count])} from the new feed"
            @async_relay.enqueue do
              apply_snapshot(
                result[:snapshot],
                status: :ready,
                message: message,
                preferred_feed_key: result[:feed_key],
                reset_content: true
              )
            end
          rescue Shoko::Error => e
            @async_relay.enqueue do
              log_error('rss_reader.add_feed_failed', e)
              update_menu(rss_status: :error, rss_message: e.message)
            end
          end
          private :perform_feed_add

          def remove_feed(feed_key)
            target = feed_key.to_s.strip
            if target.empty? || target == ALL_FEEDS_KEY
              update_menu(rss_status: :error, rss_message: 'Select a feed to remove')
              return
            end

            @rss_reader_service.remove_feed(target)
            refresh_view(
              status: default_status,
              message: 'Feed removed',
              preferred_feed_key: ALL_FEEDS_KEY,
              reset_content: true
            )
          rescue Shoko::Error => e
            log_error('rss_reader.remove_feed_failed', e)
            update_menu(rss_status: :error, rss_message: e.message)
          end

          def set_article_read(article_id, read:)
            snapshot = @rss_reader_service.set_article_read(article_id, read: read)
            refresh_after_article_update(snapshot, article_id, read ? 'Marked as read' : 'Marked as unread')
          rescue Shoko::Error => e
            log_error('rss_reader.set_article_read_failed', e)
            update_menu(rss_status: :error, rss_message: e.message)
          end

          def set_article_starred(article_id, starred:)
            snapshot = @rss_reader_service.set_article_starred(article_id, starred: starred)
            refresh_after_article_update(snapshot, article_id, starred ? 'Starred article' : 'Removed star')
          rescue Shoko::Error => e
            log_error('rss_reader.set_article_starred_failed', e)
            update_menu(rss_status: :error, rss_message: e.message)
          end

          private

          def refresh_after_article_update(snapshot, article_id, message)
            apply_snapshot(
              snapshot,
              status: default_status,
              message: message,
              preferred_feed_key: current_menu.rss_selected_feed_key,
              preferred_article_id: article_id,
              reset_content: false
            )
          end

          def apply_snapshot(snapshot, status:, message:, reset_content:, preferred_feed_key: nil,
                             preferred_article_id: nil)
            feeds = projected_feeds(snapshot)
            selected_feed_key = normalized_feed_key(feeds, preferred_feed_key)
            articles = projected_articles(snapshot, selected_feed_key)
            selected_article_id = normalized_article_id(articles, preferred_article_id)
            projections = {
              feeds: feeds,
              articles: articles,
              selected_feed_key: selected_feed_key,
              selected_article_id: selected_article_id,
            }
            view_state = { status: status, message: message, reset_content: reset_content }

            update_menu(snapshot_payload(snapshot, projections, view_state))
          end

          def default_status
            snapshot = @rss_reader_service.snapshot
            Array(snapshot[:feeds]).empty? ? :empty : :ready
          end

          def default_message(snapshot, _feeds, articles)
            return 'Press A to add a feed URL' if Array(snapshot[:feeds]).empty?
            return filter_message if filter_active?
            return empty_articles_message if articles.empty?

            'S sync  A add feed  / filter  1/2/3 scope  Z zen'
          end

          def sync_message(result)
            return 'No feeds configured' if result[:checked].zero?

            message = [
              "Synced #{result[:checked]} #{feed_word(result[:checked])}",
              "#{result[:added]} new #{article_word(result[:added])}",
            ].join(', ')
            return message if result[:errors].empty?

            "#{message}, #{result[:errors].length} #{result[:errors].length == 1 ? 'error' : 'errors'}"
          end

          def feed_word(count)
            count == 1 ? 'feed' : 'feeds'
          end

          def article_word(count)
            count == 1 ? 'article' : 'articles'
          end

          def log_error(event, error)
            @logger&.error(event, error: error.class.name, message: error.message)
          end

          def projected_feeds(snapshot)
            @rss_reader_service.feed_projection(snapshot: snapshot, scope: current_menu.rss_scope)
          end

          def normalized_feed_key(feeds, preferred_feed_key)
            @rss_reader_service.normalize_feed_key(
              feeds: feeds,
              preferred_key: preferred_feed_key || current_menu.rss_selected_feed_key
            )
          end

          def projected_articles(snapshot, selected_feed_key)
            @rss_reader_service.article_projection(
              snapshot: snapshot,
              selected_feed_key: selected_feed_key,
              scope: current_menu.rss_scope,
              query: current_menu.rss_filter_query
            )
          end

          def normalized_article_id(articles, preferred_article_id)
            @rss_reader_service.normalize_article_id(
              articles: articles,
              preferred_id: preferred_article_id || current_menu.rss_selected_article_id
            )
          end

          def snapshot_payload(snapshot, projections, view_state)
            {
              rss_feeds: projections[:feeds],
              rss_articles: projections[:articles],
              rss_selected_feed_key: projections[:selected_feed_key],
              rss_selected_article_id: projections[:selected_article_id],
              rss_last_synced_at: @rss_reader_service.last_synced_at(snapshot),
              rss_status: view_state[:status],
              rss_message: view_state[:message] ||
                default_message(snapshot, projections[:feeds], projections[:articles]),
            }.then { |payload| view_state[:reset_content] ? payload.merge(rss_content_scroll: 0) : payload }
          end

          def filter_active?
            current_menu.rss_filter_query.to_s.strip != ''
          end

          def filter_message
            "Filter active: #{current_menu.rss_filter_query.to_s.strip}"
          end

          def empty_articles_message
            case current_menu.rss_scope&.to_sym
            when :unread then 'No unread articles'
            when :starred then 'No starred articles'
            else 'No cached articles yet. Press S to sync.'
            end
          end
        end
      end
    end
  end
end
