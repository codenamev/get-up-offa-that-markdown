# frozen_string_literal: true

# Expands the bundled Hunspell dictionary (data/en/en.dic and en.aff) into plain word lists the
# app reads without any gem: data/en/words.txt (every accepted spelling) and data/en/nosuggest.txt
# (accepted, but never offered as a correction). Run it again whenever the dictionary changes:
#
#   ruby tools/build_wordlist.rb
#
# It handles what this en_US affix file uses: PFX and SFX rules with strip, add and condition,
# cross products between them, the NOSUGGEST flag, and ONLYINCOMPOUND (number suffixes such as
# "st" in "1st", which are not words of their own). COMPOUNDRULE only builds ordinals (1st, 22nd);
# the app checks letters only, so those are left out.

ROOT = File.expand_path("../data/en", __dir__)

Affix = Struct.new(:kind, :flag, :cross, :strip, :add, :condition, :add_flags)

def condition_regexp(kind, condition)
  return nil if condition == "."

  kind == :sfx ? /#{condition}\z/ : /\A#{condition}/
end

def read_affixes(path)
  rules = Hash.new { |h, k| h[k] = [] }
  cross = {}
  flags = {}
  File.foreach(path, encoding: "UTF-8") do |line|
    parts = line.split
    case parts[0]
    when "NOSUGGEST" then flags[:nosuggest] = parts[1]
    when "ONLYINCOMPOUND" then flags[:onlyincompound] = parts[1]
    when "PFX", "SFX"
      kind = parts[0] == "PFX" ? :pfx : :sfx
      if parts.size == 4 # a group's header: flag, cross product (Y/N), rule count
        cross[parts[1]] = parts[2] == "Y"
        next
      end
      add, add_flags = parts[3].split("/", 2)
      add = "" if add == "0"
      strip = parts[2] == "0" ? "" : parts[2]
      rules[parts[1]] << Affix.new(kind, parts[1], cross.fetch(parts[1]), strip, add, condition_regexp(kind, parts[4]), add_flags.to_s)
    end
  end
  [rules, flags]
end

def apply(rule, word)
  return nil if rule.condition && !word.match?(rule.condition)

  if rule.kind == :sfx
    return nil unless word.end_with?(rule.strip)

    word[0, word.length - rule.strip.length] + rule.add
  else
    return nil unless word.start_with?(rule.strip)

    rule.add + word[rule.strip.length..]
  end
end

rules, flags = read_affixes(File.join(ROOT, "en.aff"))
words = {}
nosuggest = {}
File.foreach(File.join(ROOT, "en.dic"), encoding: "UTF-8").with_index do |line, i|
  next if i.zero? # the word count

  stem, stem_flags = line.chomp.split("/", 2)
  next if stem.nil? || stem.empty?

  stem_flags = stem_flags.to_s
  next if stem_flags.include?(flags[:onlyincompound])

  taboo = stem_flags.include?(flags[:nosuggest])
  forms = [stem]
  suffixed = []
  stem_flags.each_char do |flag|
    rules.fetch(flag, []).each do |rule|
      next unless rule.kind == :sfx

      form = apply(rule, stem) or next
      forms << form
      suffixed << [form, rule]
      # A suffix's own continuation flags (en_US uses a few), one level deep.
      rule.add_flags.each_char do |more|
        rules.fetch(more, []).each { |r| (f = apply(r, form)) && forms << f }
      end
    end
  end
  stem_flags.each_char do |flag|
    rules.fetch(flag, []).each do |rule|
      next unless rule.kind == :pfx

      form = apply(rule, stem) or next
      forms << form
      next unless rule.cross

      suffixed.each { |suffixed_form, sfx| sfx.cross && (f = apply(rule, suffixed_form)) && forms << f }
    end
  end
  forms.each do |form|
    words[form] = true
    nosuggest[form] = true if taboo
  end
end

File.write(File.join(ROOT, "words.txt"), words.keys.sort.join("\n") + "\n")
File.write(File.join(ROOT, "nosuggest.txt"), nosuggest.keys.sort.join("\n") + "\n")
puts "#{words.size} words, #{nosuggest.size} never suggested"
