require "minitest/autorun"
require_relative "../spelling"

class SpellingTest < Minitest::Test
  CHECKER = Spelling.new

  def test_markdown_prose_has_exact_unicode_byte_ranges_and_code_and_urls_are_excluded
    source = <<~MD
      # 😀 日本 helo

      **mispelled** [helo](https://wrng.invalid) `wrng`
      https://wrng.invalid person@wrng.invalid &amp;

      ```ruby
      wrng
      ```

          wrng
    MD
    findings = CHECKER.check(source)
    assert_equal %w[helo mispelled helo], findings.map(&:word)
    assert_equal findings.map(&:word), findings.map { |f| source.byteslice(f.first...f.last) }
    assert_equal "# 😀 日本 ".bytesize, findings.first.first
  end

  def test_first_suggestion_is_one_edit_away_with_case_preserved
    assert_equal "hello", CHECKER.replacement("helo")
    assert_equal "Hello", CHECKER.replacement("Helo")
    assert_equal "misspelled", CHECKER.replacement("mispelled")
    assert_equal "the", CHECKER.replacement("teh")
    %w[HELO heLo xqzvvv].each { |word| assert_nil CHECKER.replacement(word) }
  end

  def test_autocorrect_requires_a_completed_standalone_word
    source = "helo Helo HELO heLo foo.helo helo-bar helo_name abc123helo helo "
    result = correct(source, previous: "")
    assert_equal "hello Hello HELO heLo foo.helo helo-bar helo_name abc123helo hello ", result
    assert_equal "helo", correct("helo", previous: "")
    assert_equal "mispelled ", correct("mispelled ", previous: "mispelled x")
  end

  def test_only_the_edited_region_changes_and_utf8_is_preserved
    previous = "helo 😀 café helo"
    source = "#{previous} "
    result = correct(source, previous: previous)
    assert_equal "helo 😀 café hello ", result
    assert_equal Encoding::UTF_8, result.encoding
    assert result.valid_encoding?
  end

  def test_pasted_shorter_text_can_be_corrected
    assert_equal "hello ", correct("helo ", previous: "some longer text")
  end

  def test_case_follows_hunspell
    assert CHECKER.correct?("hello")
    assert CHECKER.correct?("Hello"), "a lowercase word may start a sentence"
    assert CHECKER.correct?("HELLO"), "or be shouted"
    assert CHECKER.correct?("America")
    refute CHECKER.correct?("america"), "a name keeps its capital"
    assert CHECKER.correct?("don’t"), "a curly apostrophe reads as a straight one"
  end

  def test_autocorrect_only_takes_a_single_obvious_fix
    assert_equal "receive", CHECKER.replacement("recieve")
    assert_equal "until", CHECKER.replacement("untill")
    assert_nil CHECKER.replacement("wierd"), "weird or wired"
    assert_nil CHECKER.replacement("brwn"), "brown or brawn"
  end

  def test_a_word_never_suggested_is_still_accepted
    taboo = File.read(File.join(Spelling::DATA, "nosuggest.txt")).split("\n").first
    assert CHECKER.correct?(taboo)
    refute_equal taboo, CHECKER.replacement("#{taboo}x")
  end

  def test_an_indented_list_item_is_prose_not_code
    source = "- one\n\n    nested helo\n"
    assert_equal ["helo"], CHECKER.check(source).map(&:word)
  end

  # tools/build_wordlist.rb expands en.dic and en.aff; checked against spylls' Hunspell when made.
  def test_the_word_list_is_the_expanded_dictionary
    words = File.read(File.join(Spelling::DATA, "words.txt")).split("\n")
    assert_equal 123_699, words.size
    %w[misspelled running unhappiness happily].each { |w| assert_includes words, w }
  end

  # Each word's offset was measured by copying the text before it, so a check took time in the
  # square of the length: 120 ms a keystroke at 100 KB. Four times the text should now take
  # about four times as long, never the sixteen a quadratic check needs.
  def test_checking_grows_in_step_with_the_text
    paragraph = "Teh quick brwn fox jumps over the lazy dog, then helo again. " * 20 + "\n\n"
    small = paragraph * 80
    large = small * 4
    time = ->(text) { 3.times.map { t = Process.clock_gettime(Process::CLOCK_MONOTONIC); CHECKER.check(text); Process.clock_gettime(Process::CLOCK_MONOTONIC) - t }.min }
    time.(small)
    assert_operator time.(large) / time.(small), :<, 8, "a #{large.bytesize / 1024} KB check should grow linearly"
    assert_equal CHECKER.check(small).size * 4, CHECKER.check(large).size
  end

  private

  def correct(source, previous:)
    CHECKER.autocorrect(source, CHECKER.check(source), previous: previous, cursor: source.bytesize)
  end
end
