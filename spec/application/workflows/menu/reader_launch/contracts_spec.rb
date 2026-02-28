# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Workflows::Menu::ReaderLaunch::Contracts do
  def build_implementation(contract_module)
    Class.new do
      include contract_module
    end.new
  end

  it 'defines PathResolution contract methods' do
    implementation = build_implementation(described_class::PathResolution)

    expect { implementation.file_exists?('/books/a.epub') }.to raise_error(NotImplementedError)
    expect { implementation.valid_cache_path?('/books/a.cache') }.to raise_error(NotImplementedError)
  end

  it 'defines DocumentPreparation contract methods' do
    implementation = build_implementation(described_class::DocumentPreparation)

    expect do
      implementation.ensure_reader_document_for(path: '/books/a.epub', path_resolution: Object.new, on_error: nil)
    end.to raise_error(NotImplementedError)
    expect { implementation.ensure_background_worker(name: 'worker') }.to raise_error(NotImplementedError)
    expect do
      implementation.load_document_for('/books/a.epub', progress_reporter: nil, path_resolution: Object.new)
    end.to raise_error(NotImplementedError)
    expect { implementation.register_document(Object.new) }.to raise_error(NotImplementedError)
    expect { implementation.update_total_chapters(Object.new) }.to raise_error(NotImplementedError)
  end

  it 'defines RuntimeExecution and ProgressOrchestration contract methods' do
    runtime = build_implementation(described_class::RuntimeExecution)
    progress = build_implementation(described_class::ProgressOrchestration)

    expect do
      runtime.run_reader(path: '/books/a.epub', ensure_reader_document_for: ->(_path) { true })
    end.to raise_error(NotImplementedError)
    expect { runtime.file_not_found }.to raise_error(NotImplementedError)
    expect { runtime.handle_reader_error('/books/a.epub', RuntimeError.new('x')) }.to raise_error(NotImplementedError)

    expect do
      progress.load_and_open_with_progress(
        path: '/books/a.epub',
        prepare_reader_launch: ->(_path, _presenter) { nil },
        run_reader: ->(_path) { nil }
      )
    end.to raise_error(NotImplementedError)
    expect do
      progress.prepare_reader_launch(
        path: '/books/a.epub',
        load_document: ->(_path, _reporter) { nil },
        register_document: ->(_doc) { nil },
        update_total_chapters: ->(_doc) { nil },
        presenter: Object.new
      )
    end.to raise_error(NotImplementedError)
  end
end
