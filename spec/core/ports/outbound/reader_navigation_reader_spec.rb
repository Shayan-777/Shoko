# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shoko::Application::Ports::ReaderNavigationReader do
  let(:implementation) do
    Class.new do
      include Shoko::Application::Ports::ReaderNavigationReader
    end.new
  end

  it 'defines required navigation reader methods' do
    expect { implementation.current_chapter }.to raise_error(NotImplementedError)
    expect { implementation.total_chapters }.to raise_error(NotImplementedError)
    expect { implementation.current_page_index }.to raise_error(NotImplementedError)
    expect { implementation.left_page }.to raise_error(NotImplementedError)
    expect { implementation.right_page }.to raise_error(NotImplementedError)
    expect { implementation.single_page }.to raise_error(NotImplementedError)
    expect { implementation.current_page }.to raise_error(NotImplementedError)
    expect { implementation.page_map }.to raise_error(NotImplementedError)
    expect { implementation.total_pages }.to raise_error(NotImplementedError)
    expect { implementation.pending_progress }.to raise_error(NotImplementedError)
    expect { implementation.book_path }.to raise_error(NotImplementedError)
  end
end
