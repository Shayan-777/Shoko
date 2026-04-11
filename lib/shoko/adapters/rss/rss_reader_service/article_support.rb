# frozen_string_literal: true

module Shoko
  module Adapters
    module Rss
      # Article merge, retention, and record-building helpers for RSS reader sync.
      module RssReaderServiceArticleSupport
        private

        def merge_feed_articles(existing_articles, parsed_articles, feed_id_value)
          refreshed = refreshed_articles(existing_articles, parsed_articles, feed_id_value)
          merged = refreshed + retained_existing_articles(existing_articles, refreshed)
          retained_articles(merged).sort_by { |article| article_sort_tuple(article) }
        end

        def build_article_record(feed_id_value, payload, existing_index)
          title = sanitized_article_title(payload)
          return nil unless title

          article_id_value = article_id(feed_id_value, payload)
          existing = existing_index[article_id_value]
          summary = sanitized_article_summary(payload)
          content = sanitized_article_content(payload, summary)
          article_data = {
            id: article_id_value,
            title: title,
            summary: summary,
            content: content,
          }

          Shoko::Core::Models::RssArticle.new(
            **article_record_attributes(feed_id_value, payload, existing, article_data)
          )
        end

        def replace_feed_articles(all_articles, feed_id_value, replacement)
          Array(all_articles).reject { |article| article.feed_id == feed_id_value } + Array(replacement)
        end

        def article_id(feed_id_value, payload)
          basis = [feed_id_value.to_s, article_identity(payload)].join('|')
          Digest::SHA256.hexdigest(basis)
        end

        def refreshed_articles(existing_articles, parsed_articles, feed_id_value)
          existing_index = index_articles(existing_articles)
          Array(parsed_articles).filter_map do |payload|
            build_article_record(feed_id_value, payload, existing_index)
          end
        end

        def retained_existing_articles(existing_articles, refreshed_articles)
          refreshed_ids = refreshed_articles.map(&:id)
          Array(existing_articles).reject { |article| refreshed_ids.include?(article.id) }
        end

        def retained_articles(articles)
          preserve, remainder = Array(articles).partition { |article| article.starred || !article.read }
          preserve + remainder.first(retained_remainder_limit(preserve.length))
        end

        def retained_remainder_limit(preserve_length)
          [self.class::MAX_ARTICLES_PER_FEED - preserve_length, 0].max
        end

        def index_articles(articles)
          Array(articles).to_h { |article| [article.id, article] }
        end

        def article_record_attributes(feed_id_value, payload, existing, article_data)
          {
            id: article_data[:id],
            feed_id: feed_id_value,
            title: article_data[:title],
            summary: article_data[:summary],
            content: article_data[:content],
            published_at: sanitize_time(payload[:published_at]) || existing&.published_at || timestamp,
            fetched_at: timestamp,
          }.merge(article_text_attributes(payload)).merge(article_state_attributes(existing))
        end

        def sanitized_article_title(payload)
          title = sanitize_text(payload[:title], preserve_newlines: false, max_length: self.class::MAX_TITLE_LENGTH)
          return nil if title.to_s.strip.empty?

          title
        end

        def sanitized_article_summary(payload)
          sanitize_text(payload[:summary], preserve_newlines: true, max_length: self.class::MAX_SUMMARY_LENGTH)
        end

        def sanitized_article_content(payload, summary)
          content_source = payload[:content].to_s.strip.empty? ? summary : payload[:content]
          sanitize_text(content_source, preserve_newlines: true, max_length: self.class::MAX_CONTENT_LENGTH)
        end

        def article_identity(payload)
          guid = payload[:guid].to_s.strip
          return "guid:#{guid}" unless guid.empty?

          url = payload[:url].to_s.strip
          return "url:#{url}" unless url.empty?

          [
            "title:#{payload[:title].to_s.strip}",
            "published:#{sanitize_time(payload[:published_at])}",
          ].join('|')
        end

        def article_text_attributes(payload)
          {
            guid: sanitize_text(payload[:guid], max_length: 600),
            author: sanitize_text(
              payload[:author],
              preserve_newlines: false,
              max_length: self.class::MAX_AUTHOR_LENGTH
            ),
            url: sanitize_text(payload[:url], preserve_newlines: false, max_length: 600),
          }
        end

        def article_state_attributes(existing)
          {
            read: existing&.read == true,
            starred: existing&.starred == true,
          }
        end
      end
    end
  end
end
