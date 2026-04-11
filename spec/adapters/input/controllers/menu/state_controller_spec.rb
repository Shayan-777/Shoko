# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Adapters::Input::Controllers::Menu::StateController do
  let(:catalog) { instance_double('Catalog', start_scan: nil) }
  let(:reader_launch_service) do
    instance_double(
      'ReaderLaunchService',
      open_selected_book: nil,
      open_book: nil,
      run_reader: nil,
      load_and_open_with_progress: nil,
      file_not_found: nil,
      handle_reader_error: nil,
      valid_cache_path?: true
    )
  end
  let(:download_workflow) { instance_double('DownloadWorkflow', search_downloads: nil, download_book: nil) }
  let(:dictionary_workflow) { instance_double('DictionaryWorkflow', fetch_dictionary_catalog: nil, download_dictionary: nil) }
  let(:translator_workflow) { instance_double('TranslatorWorkflow', fetch_languages: [], translate_text: nil) }
  let(:rss_reader_workflow) do
    instance_double(
      'RssReaderWorkflow',
      open_reader: nil,
      refresh_view: nil,
      sync_feeds: nil,
      add_feed: nil,
      remove_feed: nil,
      set_article_read: nil,
      set_article_starred: nil
    )
  end
  let(:annotation_workflow) do
    instance_double(
      'AnnotationWorkflow',
      open_selected_annotation: nil,
      open_selected_annotation_for_edit: nil,
      delete_selected_annotation: nil,
      save_current_annotation_edit: nil
    )
  end

  subject(:controller) do
    workflows = described_class::WorkflowDependencies.new(
      download_workflow: download_workflow,
      dictionary_workflow: dictionary_workflow,
      translator_workflow: translator_workflow,
      rss_reader_workflow: rss_reader_workflow,
      annotation_workflow: annotation_workflow
    ).validate!
    deps = described_class::Dependencies.new(
      reader_launch_service: reader_launch_service,
      workflows: workflows,
      catalog: catalog
    ).validate!
    described_class.new(deps: deps)
  end

  it 'delegates reader actions to reader launch service' do
    error = RuntimeError.new('boom')

    controller.open_selected_book
    controller.open_book('/tmp/book.epub')
    controller.run_reader('/tmp/book.epub')
    controller.load_and_open_with_progress('/tmp/book.epub')
    controller.file_not_found
    controller.handle_reader_error('/tmp/book.epub', error)
    controller.valid_cache_path?('/tmp/book.cache')

    expect(reader_launch_service).to have_received(:open_selected_book)
    expect(reader_launch_service).to have_received(:open_book).with('/tmp/book.epub')
    expect(reader_launch_service).to have_received(:run_reader).with('/tmp/book.epub')
    expect(reader_launch_service).to have_received(:load_and_open_with_progress).with('/tmp/book.epub')
    expect(reader_launch_service).to have_received(:file_not_found)
    expect(reader_launch_service).to have_received(:handle_reader_error).with('/tmp/book.epub', error)
    expect(reader_launch_service).to have_received(:valid_cache_path?).with('/tmp/book.cache')
  end

  it 'delegates workflow actions to composed workflows' do
    controller.search_downloads(query: 'austen')
    controller.download_book({ title: 'Persuasion' })
    controller.fetch_dictionary_catalog
    controller.download_dictionary({ name: 'en-en' })
    controller.fetch_translation_languages(force: true)
    controller.translate_text(text: 'Hallo', source_lang: 'auto', target_lang: 'en')
    controller.open_rss_reader
    controller.refresh_rss_reader(
      status: :ready,
      message: 'Refreshed',
      preferred_feed_key: 'feed-1',
      preferred_article_id: 'article-1',
      reset_content: true
    )
    controller.sync_rss_feeds
    controller.add_rss_feed('https://example.com/feed.xml')
    controller.remove_rss_feed('feed-1')
    controller.set_rss_article_read('article-1', read: true)
    controller.set_rss_article_starred('article-1', starred: true)
    controller.open_selected_annotation
    controller.open_selected_annotation_for_edit
    controller.delete_selected_annotation
    controller.save_current_annotation_edit

    expect(download_workflow).to have_received(:search_downloads).with(query: 'austen', page_url: nil)
    expect(download_workflow).to have_received(:download_book).with({ title: 'Persuasion' })
    expect(dictionary_workflow).to have_received(:fetch_dictionary_catalog)
    expect(dictionary_workflow).to have_received(:download_dictionary).with({ name: 'en-en' })
    expect(translator_workflow).to have_received(:fetch_languages).with(force: true)
    expect(translator_workflow).to have_received(:translate_text).with(
      text: 'Hallo',
      source_lang: 'auto',
      target_lang: 'en'
    )
    expect(rss_reader_workflow).to have_received(:open_reader)
    expect(rss_reader_workflow).to have_received(:refresh_view).with(
      status: :ready,
      message: 'Refreshed',
      preferred_feed_key: 'feed-1',
      preferred_article_id: 'article-1',
      reset_content: true
    )
    expect(rss_reader_workflow).to have_received(:sync_feeds)
    expect(rss_reader_workflow).to have_received(:add_feed).with('https://example.com/feed.xml')
    expect(rss_reader_workflow).to have_received(:remove_feed).with('feed-1')
    expect(rss_reader_workflow).to have_received(:set_article_read).with('article-1', read: true)
    expect(rss_reader_workflow).to have_received(:set_article_starred).with('article-1', starred: true)
    expect(annotation_workflow).to have_received(:open_selected_annotation)
    expect(annotation_workflow).to have_received(:open_selected_annotation_for_edit)
    expect(annotation_workflow).to have_received(:delete_selected_annotation)
    expect(annotation_workflow).to have_received(:save_current_annotation_edit)
  end

  it 'refreshes catalog scan through catalog service' do
    controller.refresh_scan(force: true)
    expect(catalog).to have_received(:start_scan).with(force: true)
  end
end
