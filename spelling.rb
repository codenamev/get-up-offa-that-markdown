# frozen_string_literal: true

require "commonmarker"
require "kotoshu"
require "kotoshu/algorithms/edit_distance"

class Spelling
  WORD = /(?<![\p{L}\p{M}\p{N}_])[\p{Latin}\p{M}]+(?:['’][\p{Latin}\p{M}]+)*(?![\p{L}\p{M}\p{N}_])/
  REPLACEMENT = /\A[\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)*\z/
  NON_PROSE = %r{(?:https?://|mailto:|www\.)[^\s<>]+|[\w.+-]+@[\w.-]+\.[a-z]+|&(?:\#x[0-9a-f]+|\#\d+|[a-z][a-z0-9]+);|\\[[:punct:]]}i
  Finding = Struct.new(:word, :first, :last, keyword_init: true)

  def initialize
    root = File.join(__dir__, "data", "en")
    dictionary = Kotoshu::Dictionary::Hunspell.new(
      dic_path: File.join(root, "en.dic"), aff_path: File.join(root, "en.aff"), language_code: "en"
    )
    config = Kotoshu::Configuration.new(language: "en", offline: true, personal_dictionary: false, backend: "ruby")
    @checker = Kotoshu::Spellchecker.new(dictionary: dictionary, config: config)
    @verdicts = {}
    @replacements = {}
  end

  # All ranges crossing the native renderer boundary are UTF-8 byte offsets.
  def check(source)
    lines = source.lines
    offsets = [0]
    lines.each { |line| offsets << offsets.last + line.bytesize }
    document = Commonmarker.parse(source, options: { parse: { smart: false }, extension: { shortcodes: false } })
    findings = []
    document.walk do |node|
      next unless node.type == :text

      location = node.source_position
      first = offsets.fetch(location.fetch(:start_line) - 1) + location.fetch(:start_column) - 1
      last = offsets.fetch(location.fetch(:end_line) - 1) + location.fetch(:end_column)
      raw = source.byteslice(first...last)
      # Mask instead of deleting so the original byte positions stay intact.
      prose = raw.gsub(NON_PROSE) { |match| " " * match.bytesize }
      prose.to_enum(:scan, WORD).each do
        match = Regexp.last_match
        word = match[0]
        start = first + prose[0...match.begin(0)].bytesize
        finish = start + word.bytesize
        next if correct?(word)

        findings << Finding.new(word: word, first: start, last: finish)
      end
    end
    findings
  end

  def correct?(word)
    return @verdicts[word] if @verdicts.key?(word)

    @verdicts.clear if @verdicts.size >= 4096
    @verdicts[word] = @checker.correct?(word)
  end

  def replacement(word)
    return @replacements[word] if @replacements.key?(word)

    @replacements.clear if @replacements.size >= 4096
    @replacements[word] = begin
      if word == word.downcase || (word == word.capitalize && word != word.upcase)
        suggestion = @checker.suggest(word, max_suggestions: 3).to_words.first&.downcase
        if suggestion && REPLACEMENT.match?(suggestion) &&
            Kotoshu::Algorithms::EditDistance.distance_with_threshold(word.downcase, suggestion, 1) == 1
          candidate = word == word.downcase ? suggestion : suggestion.capitalize
          candidate if correct?(candidate)
        end
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
end
