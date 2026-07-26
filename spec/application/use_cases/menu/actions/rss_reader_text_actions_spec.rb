# frozen_string_literal: true

require 'spec_helper'

# The four actions the reading pane offers over a selection, plus in-article
# find. Each re-enters the use-case layer as an intent, the way the book
# reader's popup does, so the use case owns what the action means.
RSpec.describe Shoko::Application::UseCases::Menu::Actions::RssReader, 'text actions' do
  class TextActionSessionStore
    include Shoko::Application::Ports::Outbound::MenuSessionStore
    def initialize(snapshot) = @snapshot = snapshot
    attr_reader :snapshot
    def load = @snapshot
    def save(next_snapshot) = @snapshot = next_snapshot
  end

  class TextActionTransientStore
    include Shoko::Application::Ports::Outbound::MenuTransientStore
    def initialize(snapshot) = @snapshot = snapshot
    attr_reader :snapshot
    def load = @snapshot
    def save(next_snapshot) = @snapshot = next_snapshot
  end

  let(:session) do
    TextActionSessionStore.new(Shoko::Application::Ports::Outbound::State::MenuSessionSnapshot.build({}))
  end
  let(:transient) do
    TextActionTransientStore.new(
      Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(
        rss_selection: { start_index: 4, end_index: 10, text: 'Drohne',
                         prefix: 'Die ', suffix: ' kam.' }
      )
    )
  end
  let(:workflow) { instance_spy(Shoko::Adapters::Input::Controllers::Menu::StateController) }
  subject(:action) do
    described_class.new(menu_session_store: session, rss_reader_workflow: workflow,
                        menu_transient_store: transient)
  end

  def menu = Shoko::Application::Ports::Outbound::State::MenuSnapshot.build(
    session.snapshot.to_h.merge(transient.snapshot.to_h)
  )

  describe 'copy' do
    it 'sends the selected text to the workflow' do
      action.call(:rss_reader_copy_selection)

      expect(workflow).to have_received(:copy_rss_selection).with('Drohne')
    end

    it 'closes the actions menu afterwards' do
      action.call(:rss_reader_copy_selection)

      expect(menu.rss_context_menu).to be_nil
    end
  end

  describe 'translate' do
    it 'pre-fills the translator with the selection and opens it' do
      action.call(:rss_reader_translate_selection)

      expect(menu.translator_input_text).to eq('Drohne')
      expect(menu.translator_input_cursor).to eq(6)
      expect(menu.mode).to eq(:translator)
    end

    it 'clears any stale translator selection so the new text is not partly highlighted' do
      action.call(:rss_reader_translate_selection)

      expect(menu.translator_selection).to be_nil
      expect(menu.translator_context_menu).to be_nil
    end
  end

  describe 'look up' do
    it 'asks the workflow to look the selection up' do
      action.call(:rss_reader_lookup_selection)

      expect(workflow).to have_received(:look_up_rss_selection).with('Drohne')
    end
  end

  describe 'annotate' do
    it 'passes the quote and its surrounding words so the note can be re-located' do
      action.call(:rss_reader_annotate_selection)

      expect(workflow).to have_received(:annotate_rss_selection)
        .with(text: 'Drohne', prefix: 'Die ', suffix: ' kam.')
    end

    it 'drops the selection once the note is made' do
      action.call(:rss_reader_annotate_selection)

      expect(menu.rss_selection).to be_nil
    end
  end

  describe 'with nothing selected' do
    let(:transient) do
      TextActionTransientStore.new(
        Shoko::Application::Ports::Outbound::State::MenuTransientSnapshot.build(rss_selection: nil)
      )
    end

    it 'does nothing but close the menu' do
      %i[rss_reader_copy_selection rss_reader_lookup_selection
         rss_reader_translate_selection rss_reader_annotate_selection].each do |intent|
        action.call(intent)
      end

      expect(workflow).not_to have_received(:copy_rss_selection)
      expect(workflow).not_to have_received(:look_up_rss_selection)
      expect(workflow).not_to have_received(:annotate_rss_selection)
      expect(menu.mode).not_to eq(:translator)
    end
  end

  describe 'in-article find' do
    it 'opens the find bar with the caret after the existing query' do
      transient.save(transient.snapshot.with(rss_find_active: false))
      session.save(session.snapshot.with(rss_find_query: 'dro'))

      action.call(:rss_reader_open_find)

      expect(menu.mode).to eq(:rss_reader_find)
      expect(menu.rss_find_active).to be(true)
      expect(menu.rss_find_cursor).to eq(3)
    end

    it 'edits the query and restarts from the first match' do
      session.save(session.snapshot.with(rss_find_query: 'dro', rss_find_cursor: 3))
      transient.save(transient.snapshot.with(rss_find_index: 4))

      action.call(:edit_rss_find, Shoko::Application::UseCases::Requests::EditOp.new(operation: :insert, text: 'h'))

      expect(menu.rss_find_query).to eq('droh')
      expect(menu.rss_find_index).to eq(0)
    end

    it 'returns to the article on submit, leaving the matches highlighted' do
      action.call(:rss_reader_submit_find)

      expect(menu.mode).to eq(:rss_reader)
      expect(menu.rss_focus).to eq(:content)
    end

    it 'steps forward and back through the matches' do
      action.call(:rss_reader_next_match)
      action.call(:rss_reader_next_match)

      expect(menu.rss_find_index).to eq(2)

      action.call(:rss_reader_prev_match)

      expect(menu.rss_find_index).to eq(1)
    end

    it 'clears the query when the find is closed' do
      session.save(session.snapshot.with(rss_find_query: 'drohne'))

      action.call(:rss_reader_close_find)

      expect(menu.rss_find_query).to eq('')
      expect(menu.rss_find_active).to be(false)
      expect(menu.mode).to eq(:rss_reader)
    end
  end
end
