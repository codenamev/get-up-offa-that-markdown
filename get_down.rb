# Get Up Offa That Markdown: a tiny two-pane Markdown editor.
#
# Type on the left, watch it render on the right. Open and Save work on .md files,
# and whatever you are writing is kept as a draft between runs.
#
# The renderer is hand-rolled: headings, paragraphs,
# **bold**, *italic*, `code`, [links](https://...), ![images](pic.png), lists, > quotes,
# ``` fences and --- rules.

require "json"
require "fileutils"
require "pathname"
require_relative "spelling"

unless ENV["SCARPE_DISPLAY_SERVICE"] == "native" && Shoes::EditBox.method_defined?(:replace_checked)
  raise "Spell checking requires the local Scarpe spelling extension; see README.md."
end

INK = "#2b2118"
MUTED = "#8c7b6b"
PAPER = "#fffaf2"
PANEL = "#f6ecdc"
LINE = "#e6d6bd"
FUNK = "#d9480f"
MARKDOWN_FILES = /\.(md|markdown|mdown|txt)\z/i
IMAGE_FILES = /\.(png|jpe?g|gif|bmp)\z/i
CODE_BG = "#f1e6d3"
MONO = "Menlo"

DATA_DIR = if RUBY_PLATFORM.include?("darwin")
  File.join(Dir.home, "Library", "Application Support", "Get Up Offa That Markdown")
else
  File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")), "get_down")
end
DRAFT = File.join(DATA_DIR, "draft.json")

WELCOME = <<~MD
  # Get Up Offa That Markdown

  Type on the left. It renders on the right, **live**. *Good God!*

  ## The moves

  - Headings with `#`
  - **Bold**, *italic* and `code`
  - Links like [Scarpe](https://github.com/scarpe-team/scarpe) or <https://ruby-lang.org>
  - Images with `![alt](picture.png)`, beside your file or on the web
  1. Numbered lists too

  > Get up, get into it, get involved.

  ```
  puts "Hit me!"
  ```

  ---

  Open a `.md` file, or Save this one. Drop a `.md` file on the window to open it,
  or drop a picture to put it where you were typing.
MD

# Turns Markdown text into a list of blocks: [:h, level, text], [:p, text], [:ul, items],
# [:ol, items], [:quote, text], [:code, text], [:hr].
module Markdown
  module_function

  def blocks(source)
    lines = source.lines.map(&:chomp)
    out = []
    until lines.empty?
      line = lines.shift
      case line
      when /\A\s*\z/ then next
      when /\A```/
        code = []
        code << lines.shift until lines.empty? || lines.first.start_with?("```")
        lines.shift
        out << [:code, code.join("\n")]
      when /\A(\#{1,6})\s+(.*)/ then out << [:h, $1.size, $2]
      when /\A\s*([-*_])(\s*\1){2,}\s*\z/ then out << [:hr]
      when /\A\s*[-*+]\s+(.*)/ then out << [:ul, [$1] + take_while_matching(lines, /\A\s*[-*+]\s+(.*)/)]
      when /\A\s*\d+[.)]\s+(.*)/ then out << [:ol, [$1] + take_while_matching(lines, /\A\s*\d+[.)]\s+(.*)/)]
      when /\A>\s?(.*)/ then out << [:quote, ([$1] + take_while_matching(lines, /\A>\s?(.*)/)).join(" ")]
      else
        para = [line]
        para << lines.shift while lines.first && !lines.first.strip.empty? && !starts_block?(lines.first)
        out << [:p, para.map(&:strip).join(" ")]
      end
    end
    out
  end

  def take_while_matching(lines, pattern)
    taken = []
    taken << lines.shift[pattern, 1] while lines.first&.match?(pattern)
    taken
  end

  def starts_block?(line)
    line.match?(/\A(```|\#{1,6}\s|\s*[-*+]\s|\s*\d+[.)]\s|>)/)
  end

  INLINE = /
    !\[(?<alt>[^\]]*)\]\((?:<(?<src>[^>]+)>|(?<src>[^)\s]+))(?:\s+"[^"]*")?\) |
    \[(?<label>[^\]]+)\]\((?:<(?<href>[^>]+)>|(?<href>[^)\s]+))(?:\s+"[^"]*")?\) |
    <(?<auto>(?:https?:\/\/|mailto:)[^>\s]+)> |
    (?<bare>https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"]) |
    \*\*(?<strong>.+?)\*\* | __(?<strong2>.+?)__ |
    \*(?<em>.+?)\* | (?<![\w])_(?<em2>.+?)_(?![\w]) |
    `(?<code>.+?)`
  /x

  # Splits a line into [kind, text, target] runs: :plain, :strong, :em, :code, :link or
  # :image (text is the alt, target the source).
  def runs(text)
    out = []
    rest = text
    while (m = INLINE.match(rest))
      out << [:plain, m.pre_match] unless m.pre_match.empty?
      out << if m[:src] then [:image, m[:alt], m[:src]]
             elsif m[:href] then [:link, m[:label], m[:href]]
             elsif m[:auto] || m[:bare] then [:link, (m[:auto] || m[:bare]).delete_prefix("mailto:"), m[:auto] || m[:bare]]
             elsif m[:strong] || m[:strong2] then [:strong, m[:strong] || m[:strong2]]
             elsif m[:em] || m[:em2] then [:em, m[:em] || m[:em2]]
             else [:code, m[:code]]
             end
      rest = m.post_match
    end
    out << [:plain, rest] unless rest.empty?
    out
  end
end

Shoes.app(title: "Get Up Offa That Markdown", width: 1040, height: 700, resizable: true) do
  def load_draft
    JSON.parse(File.read(DRAFT))
  rescue Errno::ENOENT, JSON::ParserError
    { "text" => WELCOME, "path" => nil }
  end

  def save_draft
    FileUtils.mkdir_p(DATA_DIR)
    File.write("#{DRAFT}.tmp", JSON.generate("text" => @editor.text, "path" => @path))
    File.rename("#{DRAFT}.tmp", DRAFT)
  end

  def inline(text, size)
    inline_runs(Markdown.runs(text), size)
  end

  def inline_runs(runs, size)
    runs.map do |kind, words, url|
      case kind
      when :strong then strong(words)
      when :em then em(words)
      when :code then code(words, font: MONO, size: size - 1, stroke: FUNK)
      when :link then link(words, stroke: FUNK) { follow(url) }
      when :image then link("[#{words.empty? ? "image" : words}]", stroke: FUNK) { follow(url) }
      else words
      end
    end
  end

  # Where a link or image points, made absolute: next to the open file, else from the home folder.
  def resolve(target)
    return target if target.match?(%r{\A[a-z][a-z0-9+.-]*:}i)

    File.expand_path(target.sub(/#.*\z/, ""), @path ? File.dirname(@path) : Dir.home)
  end

  # Web and mail links open in the browser and mail app; a link to a Markdown file opens it here.
  def follow(target)
    where = resolve(target)
    if where.match?(/\.(md|markdown)\z/i) && File.file?(where)
      open_path(where)
    elsif where.match?(%r{\A(https?|mailto):}i) || File.exist?(where)
      system("open", where)
    end
  end

  # A paragraph's text runs go in paras; each image in it sits on a line of its own.
  def draw_paragraph(text)
    Markdown.runs(text).chunk_while { |a, b| a[0] != :image && b[0] != :image }.each do |group|
      if group.first[0] == :image
        _, alt, src = group.first
        draw_image(alt, src)
      elsif group.any? { |_, words| !words.strip.empty? }
        group = group.map(&:dup)
        group.first[1] = group.first[1].lstrip if group.first[0] == :plain
        group.last[1] = group.last[1].rstrip if group.last[0] == :plain
        para(*inline_runs(group, 14), size: 14, stroke: INK, margin: [0, 0, 0, 12])
      end
    end
  end

  # Shows a picture at its own size, shrunk to fit the preview (then it follows the window).
  def draw_image(alt, src)
    where = resolve(src)
    remote = where.match?(%r{\Ahttps?://}i)
    unless remote || File.file?(where)
      para "Image not found: #{src}", size: 13, stroke: MUTED, font: MONO, margin: [0, 0, 0, 12]
      return
    end

    natural = image_width(where)
    room = @preview.width - 54
    width = natural && natural < room ? natural : 1.0
    stack(margin: [0, 0, 0, 12]) { image where, width: width, alt: alt.empty? ? File.basename(src) : alt }
  end

  # The width stored in a picture, asked once per source; nil when it cannot be read.
  def image_width(where)
    @image_widths ||= {}
    return @image_widths[where] if @image_widths.key?(where)

    @image_widths[where] = begin
      imagesize(where)&.first
    rescue StandardError, LoadError
      nil
    end
  end

  HEADING_SIZES = { 1 => 28, 2 => 22, 3 => 18, 4 => 16, 5 => 14, 6 => 14 }.freeze

  def draw_block(kind, *args)
    case kind
    when :h
      level, text = args
      para(*inline(text, HEADING_SIZES[level]), size: HEADING_SIZES[level], weight: "bold",
        stroke: INK, margin: [0, level == 1 ? 4 : 12, 0, 8])
    when :p
      draw_paragraph(args[0])
    when :ul, :ol
      args[0].each_with_index do |item, i|
        flow margin: [8, 0, 0, 6] do
          para(kind == :ul ? "•" : "#{i + 1}.", size: 14, stroke: FUNK, width: 26, margin: 0)
          para(*inline(item, 14), size: 14, stroke: INK, width: -34, margin: 0)
        end
      end
      stack(height: 8) {}
    when :quote
      stack margin: [0, 0, 0, 12] do
        background FUNK, width: 4
        para(*inline(args[0], 14), size: 14, stroke: MUTED, font: "Georgia", margin: [16, 4, 8, 4])
      end
    when :code
      stack margin: [0, 0, 0, 12] do
        background CODE_BG, curve: 6
        para args[0], size: 13, font: MONO, stroke: INK, margin: [12, 10, 12, 10]
      end
    when :hr
      stack(height: 25) { background LINE, top: 12, height: 1 }
    end
  end

  def render
    text = @editor.text
    previous = @rendered_text || text
    @rendered_text = text
    @spelling_timer&.stop
    @spelling_generation += 1
    generation = @spelling_generation
    @preview.clear do
      blocks = Markdown.blocks(text)
      if blocks.empty?
        para "Nothing to see yet. Get up and type something.", size: 14, stroke: MUTED, margin: 0
      end
      blocks.each { |block| draw_block(*block) }
    end
    words = text.split.size
    @status.text = "#{@path ? File.basename(@path) : "Untitled"}  ·  #{words} #{words == 1 ? "word" : "words"}"
    save_draft
    findings = @spelling.check(text)
    @editor.spelling = { text: text, ranges: findings.map { |finding| [finding.first, finding.last] } }
    context = @editor.edit_context
    if context && context["autocorrect"] && @autocorrect.checked?
      @spelling_previous ||= previous
      baseline = @spelling_previous
      @spelling_timer = timer(0.6) do
        next unless @editor.text == text && @autocorrect.checked?

        @spelling_jobs.clear
        @spelling_jobs << [generation, text, findings, baseline, context.fetch("cursor")]
      end
    else
      @spelling_previous = nil
    end
  end

  def open_file
    path = ask_open_file
    return if path.nil? || path.empty?

    open_path(path)
  end

  def open_path(path)
    @path = path
    @editor.text = File.read(path)
    render
  end

  def save_file(choose: false)
    if choose || @path.nil?
      path = ask_save_file
      return if path.nil? || path.empty?

      @path = path.end_with?(".md", ".markdown") ? path : "#{path}.md"
    end
    File.write(@path, @editor.text)
    @status.text = "Saved #{File.basename(@path)}"
  end

  # A dropped Markdown file opens; a dropped picture or any other file goes in where you were
  # typing, as an image or a link, pointing at it from the open file's folder.
  def dropped(path)
    return open_path(path) if path.match?(MARKDOWN_FILES)

    target = link_target(path)
    @editor.insert(path.match?(IMAGE_FILES) ? "![#{File.basename(path, ".*")}](#{target})" : "[#{File.basename(path)}](#{target})")
  end

  # Relative to the open file when there is one; wrapped in <> when spaces would end it early.
  def link_target(path)
    target = @path ? Pathname.new(path).relative_path_from(File.dirname(@path)).to_s : path
    target.match?(/[\s()]/) ? "<#{target}>" : target
  end

  def new_file
    @path = nil
    @editor.text = ""
    render
  end

  def autocorrect_changed
    @spelling_generation += 1
    @spelling_previous = nil
    @spelling_timer&.stop
    @spelling_jobs.clear
  end

  draft = load_draft
  @path = draft["path"]
  @spelling = Spelling.new
  @spelling_generation = 0
  @spelling_jobs = Queue.new
  @spelling_results = Queue.new
  @spelling_worker = Thread.new do
    checker = Spelling.new
    loop do
      generation, text, findings, previous, cursor = @spelling_jobs.pop
      corrected = checker.autocorrect(text, findings, previous: previous, cursor: cursor)
      @spelling_results << [generation, text, corrected]
    end
  end
  finish { @spelling_worker.kill.join }

  # Shows the panes that are switched on, sharing the width between them. One always stays on.
  def show_panes(changed)
    unless @show_write.checked? || @show_preview.checked?
      (changed == :write ? @show_preview : @show_write).checked = true
    end
    both = @show_write.checked? && @show_preview.checked?
    @write_pane.style(width: both ? 0.5 : 1.0, margin_right: both ? 10 : 20)
    @preview_pane.style(width: both ? 0.5 : 1.0, margin_left: both ? 10 : 20)
    @show_write.checked? ? @write_pane.show : @write_pane.hide
    @show_preview.checked? ? @preview_pane.show : @preview_pane.hide
  end

  # A click on a check box's label ticks it, as on any desktop.
  def flip(box, pane)
    box.checked = !box.checked?
    show_panes(pane)
  end

  background PAPER

  # the toolbar
  stack width: 1.0, height: 64 do
    background PANEL
    background LINE, bottom: 0, height: 1
    stack width: 320, margin: [20, 12, 0, 0] do
      para "Get Up Offa That ", span("Markdown", stroke: FUNK), size: 20, weight: "bold", stroke: INK, margin: 0
      @status = para "", size: 12, stroke: MUTED, wrap: "trim", margin: [0, 2, 0, 0]
    end
    flow right: 20, top: 18, width: 280 do
      button("New") { new_file }
      button("Open…") { open_file }
      button("Save") { save_file }
      button("Save As…") { save_file(choose: true) }
    end
  end

  # the two panes, which fill whatever is left of the window
  flow width: 1.0, height: -64 do
    @write_pane = stack width: 0.5, height: 1.0, margin: [20, 16, 10, 20] do
      para "WRITE", size: 11, weight: "bold", stroke: MUTED, margin: [0, 0, 0, 6]
      @editor = edit_box(draft["text"], width: 1.0, height: -20, font: MONO) { render }
    end
    @preview_pane = stack width: 0.5, height: 1.0, margin: [10, 16, 20, 20] do
      para "GET DOWN", size: 11, weight: "bold", stroke: MUTED, margin: [0, 0, 0, 6]
      stack width: 1.0, height: -20 do
        background white, curve: 8
        border LINE, curve: 8
        @preview = stack width: 1.0, height: 1.0, scroll: true, margin: [22, 18, 32, 18] do
        end
      end
    end
  end

  # which panes show, on the right of the pane labels
  flow right: 20, top: 74, width: 290 do
    @autocorrect = check { autocorrect_changed }
    @autocorrect.checked = true
    para("Autocorrect", size: 13, stroke: INK, margin: [4, 2, 16, 0]).click do
      @autocorrect.checked = !@autocorrect.checked?
      autocorrect_changed
    end
    @show_write = check { show_panes(:write) }
    para("Write", size: 13, stroke: INK, margin: [4, 2, 16, 0]).click { flip(@show_write, :write) }
    @show_preview = check { show_panes(:preview) }
    para("Preview", size: 13, stroke: INK, margin: [4, 2, 0, 0]).click { flip(@show_preview, :preview) }
  end

  drop { |path| dropped(path) }

  @show_write.checked = true
  @show_preview.checked = true
  @spelling_poller = animate(20) do
    unless @spelling_worker.alive?
      @spelling_poller.stop
      @spelling_worker.value
    end
    until @spelling_results.empty?
      generation, text, corrected = @spelling_results.pop
      next unless generation == @spelling_generation && @autocorrect.checked? && @editor.text == text

      @spelling_previous = nil
      @editor.replace_checked(text, corrected) unless corrected == text
    end
  end
  render
end
