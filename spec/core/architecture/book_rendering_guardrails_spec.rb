# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Book rendering and extraction guardrails' do
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:lib_root) { File.join(root, 'lib', 'shoko') }

  def non_comment_content(path)
    File.readlines(path).reject { |line| line.strip.start_with?('#') }.join
  rescue StandardError
    ''
  end

  it 'forbids adapter-local reader document path resolver duplication' do
    duplicate_resolver = File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'document_path_resolver.rb')

    expect(File.exist?(duplicate_resolver)).to be(false),
      "Duplicate adapter resolver must not exist: #{duplicate_resolver}"
  end

  it 'forbids removed dead BookDocument artifacts from reappearing' do
    book_document_path = File.join(lib_root, 'adapters', 'book_sources', 'book_document.rb')
    content = non_comment_content(book_document_path)
    forbidden = %w[
      @formatting_pending
      @formatting_pending_mutex
      @spine_relative_paths
      @book_payload
      enqueue_async_formatting
      assign_toc_entries
      normalize_toc_href
    ]
    offenders = forbidden.select { |pattern| content.include?(pattern) }

    expect(offenders).to be_empty,
      "Removed BookDocument dead artifacts are present: #{offenders.join(', ')}"
  end

  it 'forbids reintroduction of removed DocumentService TOC API' do
    path = File.join(lib_root, 'adapters', 'book_sources', 'document_service.rb')
    content = non_comment_content(path)

    expect(content).not_to include('def get_table_of_contents'),
      'DocumentService#get_table_of_contents is removed dead API and must not reappear'
  end
end
