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

  it 'forbids adapter-local reader document locator duplication' do
    duplicate_resolver = File.join(lib_root, 'adapters', 'input', 'controllers', 'reader', 'reader_document_locator.rb')

    expect(File.exist?(duplicate_resolver)).to be(false),
      "Duplicate adapter document locator must not exist: #{duplicate_resolver}"
  end

  it 'keeps the old book-source BookDocument deleted' do
    book_document_path = File.join(lib_root, 'adapters', 'book_sources', 'book_document.rb')

    expect(File.exist?(book_document_path)).to eq(false),
      "BookDocument is an application read model now and must not live at #{book_document_path}"
  end

  it 'keeps the old book-source DocumentService deleted' do
    path = File.join(lib_root, 'adapters', 'book_sources', 'document_service.rb')

    expect(File.exist?(path)).to eq(false),
      "Document loading orchestration belongs in application, not #{path}"
  end
end
