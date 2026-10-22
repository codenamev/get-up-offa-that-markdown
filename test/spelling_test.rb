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

  private

  def correct(source, previous:)
    CHECKER.autocorrect(source, CHECKER.check(source), previous: previous, cursor: source.bytesize)
  end
end
