# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Zero fallback outbound port contracts' do
  def build_implementation(port_module)
    Class.new do
      include port_module
    end.new
  end

  it 'defines DocumentLoader contract method' do
    implementation = build_implementation(Shoko::Application::Ports::Outbound::DocumentLoader)

    expect do
      implementation.load(path: '/tmp/book.epub', progress_reporter: nil)
    end.to raise_error(NotImplementedError)
  end

  it 'defines BackgroundWorkerBuilder contract method' do
    implementation = build_implementation(Shoko::Application::Ports::Outbound::BackgroundWorkerBuilder)

    expect do
      implementation.build(name: 'reader-background', logger: nil)
    end.to raise_error(NotImplementedError)
  end

  it 'defines ProgressRepository contract methods' do
    implementation = build_implementation(Shoko::Application::Ports::Outbound::ProgressRepository)

    expect do
      implementation.save_for_book('/tmp/book.epub', chapter_index: 1, line_offset: 10)
    end.to raise_error(NotImplementedError)
    expect { implementation.find_by_book_path('/tmp/book.epub') }.to raise_error(NotImplementedError)
    expect { implementation.find_all }.to raise_error(NotImplementedError)
    expect { implementation.exists_for_book?('/tmp/book.epub') }.to raise_error(NotImplementedError)
    expect { implementation.last_updated_at('/tmp/book.epub') }.to raise_error(NotImplementedError)
    expect { implementation.recent_books(limit: 1) }.to raise_error(NotImplementedError)
    expect do
      implementation.save_if_further('/tmp/book.epub', chapter_index: 1, line_offset: 10)
    end.to raise_error(NotImplementedError)
  end
end
