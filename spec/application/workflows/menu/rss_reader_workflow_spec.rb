# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::RssReaderWorkflow do
  class RssReaderWorkflowTestMenuSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore

    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  class RssReaderWorkflowTestMenuTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore

    attr_reader :snapshot

    def initialize(snapshot)
      @snapshot = snapshot
    end

    def load
      @snapshot
    end

    def save(snapshot)
      @snapshot = snapshot
    end
  end

  let(:service) { instance_double(Shoko::Adapters::Rss::RssReaderService) }
  let(:menu_session_store) do
    RssReaderWorkflowTestMenuSessionStore.new(
      Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build(
        mode: :rss_reader,
        rss_scope: :all,
        rss_selected_feed_key: '__all__',
        rss_selected_article_id: nil,
        rss_filter_query: '',
        rss_focus: :feeds,
        rss_content_scroll: 4
      )
    )
  end
  let(:menu_transient_store) do
    RssReaderWorkflowTestMenuTransientStore.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        rss_feeds: [],
        rss_articles: [],
        rss_status: :empty,
        rss_message: 'Press A to add a feed URL'
      )
    )
  end
  let(:snapshot) { { schema_version: 1, feeds: [:feed], articles: [:article] } }
  let(:feeds) do
    [
      { key: '__all__', title: 'All Feeds', count: 2, unread_count: 1, article_count: 2 },
      { key: 'feed-1', title: 'Daily Planet', count: 2, unread_count: 1, article_count: 2 }
    ]
  end
  let(:articles) do
    [
      { id: 'article-1', feed_id: 'feed-1', feed_title: 'Daily Planet', title: 'Morning Edition', read: false, starred: false }
    ]
  end

  subject(:workflow) do
    described_class.new(
      rss_reader_service: service,
      menu_session_store: menu_session_store,
      menu_transient_store: menu_transient_store
    )
  end

  before do
    allow(service).to receive(:snapshot).and_return(snapshot)
    allow(service).to receive(:feed_projection).and_return(feeds)
    allow(service).to receive(:normalize_feed_key).and_return('feed-1')
    allow(service).to receive(:article_projection).and_return(articles)
    allow(service).to receive(:normalize_article_id).and_return('article-1')
    allow(service).to receive(:last_synced_at).and_return('2026-04-06T08:00:00Z')
  end

  it 'populates menu session and transient state when opening the reader' do
    workflow.open_reader

    expect(menu_session_store.load.rss_selected_feed_key).to eq('feed-1')
    expect(menu_session_store.load.rss_selected_article_id).to eq('article-1')
    expect(menu_transient_store.load.rss_feeds).to eq(feeds)
    expect(menu_transient_store.load.rss_articles).to eq(articles)
    expect(menu_transient_store.load.rss_status).to eq(:ready)
    expect(menu_transient_store.load.rss_last_synced_at).to eq('2026-04-06T08:00:00Z')
  end

  it 'adds a feed and selects it in the refreshed projection' do
    allow(service).to receive(:add_feed).with('https://example.com/feed.xml').and_return(
      snapshot: snapshot,
      feed_key: 'feed-1',
      added_count: 2
    )

    workflow.add_feed('https://example.com/feed.xml')

    expect(menu_session_store.load.rss_selected_feed_key).to eq('feed-1')
    expect(menu_session_store.load.rss_content_scroll).to eq(0)
    expect(menu_transient_store.load.rss_message).to eq('Added 2 articles from the new feed')
  end

  it 'reports an error when attempting to remove the synthetic all-feeds entry' do
    workflow.remove_feed('__all__')

    expect(menu_transient_store.load.rss_status).to eq(:error)
    expect(menu_transient_store.load.rss_message).to eq('Select a feed to remove')
  end

  it 'updates article state through the service and preserves selection' do
    allow(service).to receive(:set_article_read).with('article-1', read: true).and_return(snapshot)

    workflow.set_article_read('article-1', read: true)

    expect(menu_session_store.load.rss_selected_article_id).to eq('article-1')
    expect(menu_transient_store.load.rss_message).to eq('Marked as read')
  end

  describe 'asynchronous operation' do
    let(:deferred_executor) do
      executor = Object.new
      executor.instance_variable_set(:@jobs, [])
      executor.define_singleton_method(:submit) { |&job| @jobs << job }
      executor.define_singleton_method(:run_all) { @jobs.shift.call until @jobs.empty? }
      executor
    end
    let(:relay) { Shoko::Application::Services::AsyncResultRelay.new(async_executor: deferred_executor) }

    subject(:workflow) do
      described_class.new(
        rss_reader_service: service,
        menu_session_store: menu_session_store,
        menu_transient_store: menu_transient_store,
        async_relay: relay
      )
    end

    it 'shows the syncing status immediately; the snapshot lands on drain' do
      allow(service).to receive(:sync_all).and_return(snapshot: snapshot, errors: [], checked: 1, added: 2)

      workflow.sync_feeds

      expect(menu_transient_store.load.rss_status).to eq(:syncing)
      expect(workflow.network_pending?).to be(true)

      deferred_executor.run_all
      workflow.process_pending_events

      expect(menu_transient_store.load.rss_status).to eq(:ready)
      expect(menu_transient_store.load.rss_feeds).to eq(feeds)
      expect(workflow.network_pending?).to be(false)
    end
  end
  describe 'text actions over a reading selection' do
    let(:clipboard) do
      instance_double(Shoko::Adapters::Output::Clipboard::ClipboardService, available?: true)
    end
    let(:dictionary_service) { instance_double(Shoko::Core::Services::DictionaryService) }
    let(:annotation_service) do
      instance_double(Shoko::Core::Services::AnnotationService, add: nil, list_for_book: [])
    end
    let(:article) do
      { id: 'a1', feed_id: 'f1', feed_title: 'Daily Planet', title: 'Story',
        summary: 's', content: 'c', content_blocks: [], url: 'https://example.com/story',
        published_label: 'now', read: false, starred: false }
    end
    subject(:text_workflow) do
      described_class.new(
        rss_reader_service: service,
        menu_session_store: menu_session_store,
        menu_transient_store: menu_transient_store,
        clipboard: clipboard,
        dictionary_service: dictionary_service,
        annotation_service: annotation_service,
        logger: nil
      )
    end

    before do
      menu_transient_store.save(menu_transient_store.snapshot.with(rss_articles: [article]))
      menu_session_store.save(menu_session_store.snapshot.with(rss_selected_article_id: 'a1'))
    end

    def menu_now
      Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
        menu_session_store.snapshot.to_h.merge(menu_transient_store.snapshot.to_h)
      )
    end

    describe '#copy_rss_selection' do
      it 'copies the text and reports what the clipboard said' do
        allow(clipboard).to receive(:copy_with_feedback).with('Drohne') do |&block|
          block.call(' Copied to clipboard!')
          true
        end

        text_workflow.copy_rss_selection('Drohne')

        expect(menu_now.rss_message).to eq('Copied to clipboard!')
        expect(menu_now.rss_status).to eq(:ready)
      end

      it 'reports a failed copy as an error' do
        allow(clipboard).to receive(:copy_with_feedback) do |&block|
          block.call(' Failed to copy to clipboard')
          false
        end

        text_workflow.copy_rss_selection('Drohne')

        expect(menu_now.rss_status).to eq(:error)
      end

      it 'reports rather than raises when there is no clipboard' do
        allow(clipboard).to receive(:available?).and_return(false)

        allow(clipboard).to receive(:copy_with_feedback)

        text_workflow.copy_rss_selection('Drohne')

        expect(clipboard).not_to have_received(:copy_with_feedback)
        expect(menu_now.rss_status).to eq(:error)
      end
    end

    describe '#look_up_rss_selection' do
      it 'opens the lookup view on the query straight away' do
        allow(dictionary_service).to receive(:lookup).and_return(nil)

        text_workflow.look_up_rss_selection('Haus')

        expect(menu_now.mode).to eq(:rss_reader_lookup)
        expect(menu_now.rss_lookup_query).to eq('Haus')
      end

      it 'flattens the result to plain data the state tree admits' do
        entry = Shoko::Core::Models::DictionaryEntry.new(word: 'Haus', senses: ['a building'],
                                                         translations: %w[house home])
        allow(dictionary_service).to receive(:lookup).with('Haus').and_return(
          Shoko::Core::Models::DictionaryResult.new(query: 'Haus', entries: [entry])
        )

        text_workflow.look_up_rss_selection('Haus')

        result = menu_now.rss_lookup_result
        expect(result[:entries].first[:word]).to eq('Haus')
        expect(result[:entries].first[:translations]).to eq(%w[house home])
        expect { Shoko::Shared::DeepStructure.admit(result) }.not_to raise_error
      end

      it 'reports an empty lookup rather than an empty screen' do
        allow(dictionary_service).to receive(:lookup).and_return(
          Shoko::Core::Models::DictionaryResult.new(query: 'zzz', entries: [])
        )

        text_workflow.look_up_rss_selection('zzz')

        expect(menu_now.rss_lookup_status).to eq(:empty)
      end

      it 'ignores a blank selection' do
        text_workflow.look_up_rss_selection('   ')

        expect(menu_now.mode).not_to eq(:rss_reader_lookup)
      end
    end

    describe '#annotate_rss_selection' do
      it 'anchors the note to the article by its URL' do
        text_workflow.annotate_rss_selection(text: 'Drohne', prefix: 'Die ', suffix: ' kam.')

        expect(annotation_service).to have_received(:add) do |path, draft|
          expect(path).to eq('https://example.com/story')
          expect(draft.text).to eq('Drohne')
          expect(draft.anchor.quote).to eq('Drohne')
          expect(draft.anchor.prefix).to eq('Die ')
          expect(draft.chapter_index).to eq(0)
        end
      end

      it 'falls back to the article id when the feed gave no link' do
        menu_transient_store.save(menu_transient_store.snapshot.with(rss_articles: [article.merge(url: '')]))

        text_workflow.annotate_rss_selection(text: 'Drohne')

        expect(annotation_service).to have_received(:add).with('rss:a1', anything)
      end

      it 'reports when no article is open' do
        menu_session_store.save(menu_session_store.snapshot.with(rss_selected_article_id: nil))

        text_workflow.annotate_rss_selection(text: 'Drohne')

        expect(annotation_service).not_to have_received(:add)
        expect(menu_now.rss_status).to eq(:error)
      end

      it 'confirms the note was saved' do
        text_workflow.annotate_rss_selection(text: 'Drohne')

        expect(menu_now.rss_message).to include('Annotation saved')
      end

      # The pane marks where notes were made, so the quotes have to reach state
      # as soon as one is added rather than on the next refresh.
      it 'publishes the article notes so the pane can mark them' do
        allow(annotation_service).to receive(:list_for_book).and_return(
          [{ note: 'check', anchor: { quote: 'Drohne' } }]
        )

        text_workflow.annotate_rss_selection(text: 'Drohne')

        expect(menu_now.rss_annotations).to eq([{ quote: 'Drohne', note: 'check' }])
      end

      it 'skips a stored note that has no quote' do
        allow(annotation_service).to receive(:list_for_book).and_return([{ note: 'page note', anchor: {} }])

        text_workflow.annotate_rss_selection(text: 'Drohne')

        expect(menu_now.rss_annotations).to eq([])
      end
    end
  end
end
