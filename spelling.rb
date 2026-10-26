# frozen_string_literal: true

# Spell checking for the editor, in plain Ruby so a packaged app (which carries no gems) can do
# it. Words come from data/en/words.txt, the bundled American English Hunspell dictionary
# expanded by tools/build_wordlist.rb. Markdown that is not prose (code, link targets, URLs,
# e-mail addresses, entities) is masked rather than removed, so every range is a UTF-8 byte
# offset into the text as written: what the native edit box underlines and replaces.
#
# Design and the autocorrect rules by @dblock (codenamev/get-up-offa-that-markdown#1), after
# rubocop-spellcheck: only a newly completed, standalone word in lowercase or Title case is ever
# corrected, and only to a dictionary word one edit away.
class Spelling
  WORD = /(?<![\p{L}\p{M}\p{N}_])[\p{Latin}\p{M}]+(?:['’][\p{Latin}\p{M}]+)*(?![\p{L}\p{M}\p{N}_])/
  NON_PROSE = %r{(?:https?://|mailto:|www\.)[^\s<>]+|[\w.+-]+@[\w.-]+\.[a-z]+|&(?:\#x[0-9a-f]+|\#\d+|[a-z][a-z0-9]+);|\\[[:punct:]]}i
  # Inline code, a link or image target, and an autolink or HTML tag.
  INLINE_CODE = /(`+).+?\1/
  LINK_TARGET = /(?<=\])\([^)]*\)/
  ANGLED = /<[^<>\s][^<>]*>/
  FENCE = /\A {0,3}(```|~~~)/
  LIST_ITEM = /\A\s*(?:[-*+]|\d+[.)])\s/
  # Hunspell's TRY string for this dictionary: the letters an edit may bring in.
  LETTERS = "esianrtolcdugmphbyfvkwz'".chars.freeze
  Finding = Struct.new(:word, :first, :last, keyword_init: true)

  DATA = File.join(__dir__, "data", "en")

  def initialize(words: File.join(DATA, "words.txt"), nosuggest: File.join(DATA, "nosuggest.txt"))
    @words = File.read(words, encoding: "UTF-8").split("\n").to_h { |w| [w, true] }
    @nosuggest = File.read(nosuggest, encoding: "UTF-8").split("\n").to_h { |w| [w, true] }
    # An ALL CAPS word is right when any dictionary spelling of it is ("NASA", "IPOD" for iPod).
    @upcased = @words.each_key.to_h { |w| [w.upcase, true] }
    @verdicts = {}
    @replacements = {}
  end

  # The misspelled words in Markdown source, as byte ranges.
  def check(source)
    prose = mask(source)
    findings = []
    prose.to_enum(:scan, WORD).each do
      match = Regexp.last_match
      word = match[0]
      start = prose[0...match.begin(0)].bytesize
      next if correct?(word)

      findings << Finding.new(word: word, first: start, last: start + word.bytesize)
    end
    findings
  end

  # Hunspell's case rules: a lowercase entry also takes Title and ALL CAPS, a Title entry (a
  # name) takes ALL CAPS, and anything else must match as written.
  def correct?(word)
    return @verdicts[word] if @verdicts.key?(word)

    @verdicts.clear if @verdicts.size >= 4096
    plain = word.tr("’", "'")
    @verdicts[word] = @words.key?(plain) ||
      (plain == plain.capitalize && @words.key?(plain.downcase)) ||
      (plain == plain.upcase && @upcased.key?(plain))
  end

  # The one correction autocorrect may make, or nil: lowercase and Title case words only, and
  # only when a single dictionary word fits a common slip. That is a swapped pair ("teh"), a
  # doubled letter missing or extra ("helo", "untill"), and otherwise a lone word one edit away.
  def replacement(word)
    return @replacements[word] if @replacements.key?(word)

    @replacements.clear if @replacements.size >= 4096
    @replacements[word] = begin
      title = word == word.capitalize && word != word.upcase
      if word == word.downcase || title
        fix = best_edit(word.downcase)
        fix && (title ? fix.capitalize : fix)
      end
    end
  end

  def standalone?(source, finding)
    before = source.byteslice(0...finding.first)
    after = source.byteslice(finding.last..)
    !before.match?(/[\p{L}\p{M}\p{N}_](?:[.-])?\z/) &&
      !after.match?(/\A(?:[.-])?[\p{L}\p{M}\p{N}_]/)
  end

  # Correct only words completed by this edit, never unrelated text in an opened file.
  def autocorrect(source, findings, previous:, cursor:)
    common = previous.chars.zip(source.chars).take_while { |a, b| a == b }.sum { |a, _| a.bytesize }
    suffix = previous.byteslice(common..).chars.reverse.zip(source.byteslice(common..).chars.reverse)
      .take_while { |a, b| a == b }.sum { |a, _| a.bytesize }
    return source if source.bytesize - common - suffix <= 0

    corrected = source.b.dup
    findings.reverse_each do |finding|
      next unless finding.last >= common && finding.last < cursor
      next unless standalone?(source, finding)

      word = replacement(finding.word)
      corrected[finding.first...finding.last] = word.b if word
    end
    corrected.force_encoding(Encoding::UTF_8)
  end

  private

  def suggestible?(word)
    @words.key?(word) && !@nosuggest.key?(word) && word == word.downcase
  end

  def best_edit(word)
    swapped = (0...word.length - 1).map { |i| word.dup.tap { |w| w[i], w[i + 1] = w[i + 1], w[i] } }
    doubled = (0...word.length).map { |i| word.dup.insert(i, word[i]) } +
      (1...word.length).select { |i| word[i] == word[i - 1] }.map { |i| word.dup.tap { |w| w.slice!(i) } }
    [swapped, doubled, edits(word)].each do |candidates|
      found = candidates.uniq.select { |c| c != word && suggestible?(c) }
      return found.first if found.size == 1
      return nil if found.size > 1
    end
    nil
  end

  # Every string one deletion, substitution or insertion away.
  def edits(word)
    out = []
    (0..word.length).each do |i|
      out << word[0...i] + word[i + 1..].to_s if i < word.length
      LETTERS.each do |c|
        out << word[0...i] + c + word[i + 1..].to_s if i < word.length
        out << word[0...i] + c + word[i..]
      end
    end
    out
  end

  # The source with everything that is not prose blanked to spaces, byte for byte.
  def mask(source)
    fenced = false
    indented = false
    previous_blank = true
    in_list = false
    source.lines.map do |line|
      blank = line.strip.empty?
      if line.match?(FENCE)
        fenced = !fenced
        next blanked(line)
      end
      next blanked(line) if fenced

      indented = !blank && line.match?(/\A(?: {4}|\t)/) && !in_list && (previous_blank || indented)
      # A blank line keeps a list going; an unindented line that is not an item ends it.
      in_list = line.match?(LIST_ITEM) || (in_list && (blank || line.match?(/\A\s/))) unless indented
      previous_blank = blank
      next blanked(line) if indented

      [INLINE_CODE, LINK_TARGET, ANGLED, NON_PROSE].reduce(line) { |text, pattern| text.gsub(pattern) { |m| blanked(m) } }
    end.join
  end

  # Spaces for every byte, keeping the newline so later lines keep their offsets.
  def blanked(text)
    text.end_with?("\n") ? " " * (text.bytesize - 1) + "\n" : " " * text.bytesize
  end
end
