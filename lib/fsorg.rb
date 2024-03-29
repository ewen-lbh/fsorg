# frozen_string_literal: true

require "colorize"
require "set"
require "shellwords"
require "yaml"

PERMISSIONS_PATTERN = /[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=]?[0-7]+/

def d(thing)
  p thing
  thing
end

class Fsorg # rubocop:disable Metrics/ClassLength,Style/Documentation
  attr_accessor :data, :document, :document_path, :root_directory

  def initialize(root_directory, data, document, absolute_path)
    @root_directory = root_directory
    @shell = "/usr/bin/env bash"
    @document_path = absolute_path
    @data = { HERE: @root_directory.to_s }.merge data
    @document = document
    @current_line = 0
    @current_depth = -1
  end

  def from_relative_to_root(path)
    @root_directory / path
  end

  def depth_change(line)
    change = 0
    if /\}\s*$/ =~ line
      change -= 1
    end
    if /^\s*\{/ =~ line
      change += 1
    end
    change
  end

  def preprocess
    process_front_matter
    strip_comments
    desugar
    process_includes
    # TODO: process_see
    process_for
    process_if
    turn_puts_into_runs
    ask_missing_variables
    process_root
    process_shell
  end

  def process_front_matter # rubocop:disable Metrics/MethodLength
    unless /^-+$/ =~ @document.lines(chomp: true).first
      return
    end

    # Remove front matter from document
    front_matter_raw = ""
    rest = ""
    inside_front_matter = false
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_linecur = index + 1
      if /^-+$/ =~ line
        inside_front_matter = !inside_front_matter
        next
      end

      if inside_front_matter
        front_matter_raw += "#{line}\n"
      else
        rest += "#{line}\n"
      end
    end

    front_matter = YAML.safe_load(front_matter_raw, symbolize_names: true) or {}

    @data = front_matter.merge @data
    @document = rest
  end

  def desugar # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    output = []
    inside_write_directive_shorthand = false
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_write_directive_shorthand
        if line.strip == "]"
          inside_write_directive_shorthand = false
          output << "}"
        else
          output << line
        end
      elsif /^\}(\s*ELSE\s*\{)$/.match line.strip
        output << "}"
        output << $~[1]
      elsif /^FILE\s+(?<filename>.+?)$/ =~ line.strip
        output << "RUN touch #{filename.shellescape}"
      elsif /^(\s*[^{]+?\{)([^{]+?)\}$/.match line.strip
        output << $~[1]
        output << $~[2]
        output << "}"
      elsif /^(?<filename>.+?)\s*(\s+\((?<permissions>#{PERMISSIONS_PATTERN})\))?\s*\[$/.match line.strip
        output << "WRITE #{$~[:filename]} #{$~[:permissions] ? "MODE #{$~[:permissions]}" : ""} {"
        inside_write_directive_shorthand = true
      else
        output << line
      end
    end
    @document = output.join "\n"
  end

  def strip_comments
    output = []
    @document.lines(chomp: true).each_with_index do |line, _index|
      output << if /^(?<content>.*)#\s.*$/ =~ line
        content
      else
        line
      end
    end
    @document = output.join "\n"
  end

  def process_includes # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    output = []

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if line.start_with? "INCLUDE "
        filepath = @document_path.parent.join(line.sub(/^INCLUDE /, ""))
        included_raw = File.new(filepath).read.strip
        included_fsorg = Fsorg.new(@root_directory, @data, included_raw, filepath)
        included_fsorg.preprocess
        @data = included_fsorg.data.merge @data
        output += included_fsorg.document.lines(chomp: true)
      else
        output << line
      end
    end

    @document = output.join "\n"
  end

  def store_writes
    output = []

    @document = output.join "\n"
  end

  def turn_puts_into_runs # rubocop:disable Metrics/MethodLength
    output = []
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      output << if /^PUT\s+(?<source>.+?)(\s+AS\s+(?<destination>.+?))?(\s+MODE\s+(?<permissions>.+?))?$/.match(line.strip) # rubocop:disable Lint/MixedRegexpCaptureTypes
        "RUN install -D \"$FSORG_ROOT/#{$~[:source]}\" #{($~[:destination] || $~[:source]).shellescape}" + (if $~[:permissions]
          " -m #{$~[:permissions].shellescape}"
        else
          ""
        end)
      else
        line
      end
    end

    @document = output.join "\n"
  end

  def process_for # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    output = []
    inside_for_directive = false
    body = []
    args = nil
    current_depth = 0
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_for_directive
        current_depth += depth_change line.strip
        if current_depth.zero?
          inside_for_directive = false
          output += repeat_for_each(args[:iteratee], args[:iterator], body)
        else
          body << line
        end
      elsif /^FOR\s+(?<iteratee>\w+)\s+IN\s+(?<iterator>.+?)\s*\{$/.match(line.strip)
        args = $~
        current_depth = 1
        body = []
        inside_for_directive = true
      else
        output << line
      end
      @document = output.join "\n"
    end
  end

  def repeat_for_each(iteratee, iterator, directives) # rubocop:disable Metrics/AbcSize
    output = []
    raise "[#{@document_path}:#{@current_line}]".colorize :red + "Variable '#{iterator}' not found (iterators cannot be asked for interactively). Available variables at this point: #{data.keys.join(", ")}." unless data[iterator.to_sym]
    raise "[#{@document_path}:#{@current_line}]".colorize :red + "Cannot iterate over '#{iterator}', which is of type #{data[iterator.to_sym].class}." unless data[iterator.to_sym].is_a? Array

    data[iterator.to_sym].each do |item|
      output += directives.map do |directive|
        directive.gsub "{{#{iteratee}}}", item.to_s
      end
    end
    output
  end

  def process_if # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    output = []
    inside_if = false
    body_if = []
    inside_else = false
    body_else = []
    current_condition = nil
    current_depth = 0

    @document.lines(chomp: true).each_with_index do |line, index| # rubocop:disable Metrics/BlockLength
      @current_line = index + 1
      if inside_if
        current_depth += depth_change line.strip
        if current_depth.zero?
          inside_if = false
          inside_else = false
          output += body_if if evaluates_to_true? current_condition
        else
          body_if << line
        end
      elsif inside_else
        current_depth += depth_change line.strip
        if current_depth.zero?
          inside_else = false
          inside_if = false
          output += body_else if evaluates_to_false? current_condition
          current_condition = nil
        else
          body_else << line
        end
      elsif /^IF\s+(?<condition>.+?)\s*\{$/.match(line.strip)
        current_condition = $~[:condition]
        current_depth = 1
        inside_if = true
      elsif /^(\}\s*)?ELSE\s*\{$/.match(line.strip)
        raise "[#{@document_path}:#{@current_line}] Cannot use ELSE without IF." if current_condition.nil?

        inside_else = true
        current_depth = 1
      else
        output << line
      end
      @document = output.join "\n"
    end
  end

  def evaluates_to_false?(condition)
    !evaluates_to_true? condition
  end

  def evaluates_to_true?(condition)
    raise "[#{@document_path}:#{@current_line}] Variable '#{condition}' not found. Available variables at this point: #{data.keys.join(", ")}." unless @data.include? condition.to_sym

    @data[condition.to_sym]
  end

  def ask_missing_variables
    @document.scan(/\{\{(?<variable>[^}]+?)\}\}/) do |variable|
      @data[variable[0].to_sym] = :ask unless @data.include? variable[0].to_sym
    end

    @data.each do |key, value|
      if value == :ask
        print "#{key}? "
        @data[key] = YAML.safe_load $stdin.gets.chomp
      end
    end
  end

  def process_root # rubocop:disable Metrics/MethodLength
    @document = @document.lines(chomp: true).map.with_index do |line, index|
      @current_line = index + 1
      if /^ROOT\s+(?<root>.+?)$/.match line.strip
        @root_directory = if $~[:root].start_with? "/"
            Pathname.new $~[:root]
          else
            @root_directory.join $~[:root]
          end
        ""
      else
        line
      end
    end.join "\n"
  end

  def process_shell
    @document = @document.lines(chomp: true).map.with_index do |line, index|
      @current_line = index + 1
      if /^SHELL\s+(?<shell>.+?)$/.match line.strip
        @shell = $~[:shell]
        ""
      else
        line
      end
    end.join "\n"
  end

  def current_location
    @data[:HERE]
  end

  def walk(dry_run, quiet, verbose) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    current_path = [@root_directory]
    @data[:HERE] = @root_directory
    file_to_write = {}
    inside_write_directive = -> { !file_to_write.keys.empty? }
    current_path_as_pathname = -> { current_path.reduce(Pathname.new("")) { |path, fragment| path.join fragment } }

    puts "Data is #{@data.except :HERE}".light_black if verbose

    @document.lines(chomp: true).each_with_index do |line, index| # rubocop:disable Metrics/BlockLength
      @current_line = index + 1
      @current_depth = current_path.length - 1

      @data.each do |key, value|
        line = line.gsub "{{#{key}}}", value.to_s
      end

      if inside_write_directive.call
        if line.strip == "}"
          do_write file_to_write, dry_run, quiet
          file_to_write = {}
        else
          file_to_write[:content] += "#{line}\n"
        end
      elsif /^WRITE(\s+INTO)?\s+(?<destination>.+?)(?:\s+MODE\s+(?<permissions>.+?))?\s*\{$/.match line.strip # rubocop:disable Lint/MixedRegexpCaptureTypes
        file_to_write = $~.named_captures.transform_keys(&:to_sym)
        file_to_write[:content] = ""
      elsif /^(?<leaf>.+?)\s+\{/ =~ line.strip
        current_path << leaf
        @data[:HERE] = current_path_as_pathname.call
        puts "currenly #{current_path.map(&:to_s).join " -> "}".light_black if verbose
        do_mkpath current_location, dry_run, quiet
      elsif line.strip == "}"
        current_path.pop
        @data[:HERE] = current_path_as_pathname.call
        puts "currenly #{current_path.map(&:to_s).join " -> "}".light_black if verbose
      elsif /^RUN\s+(?<command>.+?)$/ =~ line.strip
        environment = {
          "FSORG_ROOT" => @root_directory.to_s,
          "HERE" => @data[:HERE].relative_path_from(@root_directory).to_s,
          "CWD" => Dir.pwd,
          "DOCUMENT_DIR" => @document_path.parent.to_s,
        }
        do_run command, current_location, environment, dry_run, quiet, verbose
      end
    end
  end

  def do_mkpath(path, dry_run, quiet)
    puts "#{"  " * @current_depth}+ ".cyan.bold + path.relative_path_from(@root_directory).to_s unless quiet
    path.mkpath unless dry_run
  end

  def do_write(future_file, dry_run, quiet) # rubocop:disable Metrics/AbcSize
    indentation = "  " * @current_depth
    dest = from_relative_to_root(current_location) / future_file[:destination]
    do_mkpath dest.parent, dry_run, quiet unless dest.parent.relative_path_from(@root_directory).to_s == "."

    unless quiet
      puts "#{indentation}> ".cyan.bold + dest.relative_path_from(@root_directory).to_s + (future_file[:permissions] ? " mode #{future_file[:permissions]}".yellow : "")
    end

    return if dry_run

    dest.write ensure_final_newline(dedent(replace_data(future_file[:content])))
    # Not using dest.chmod as the syntax for permissions is more than just integers,
    # and matches in fact the exact syntax of chmod's argument, per the manpage, chmod(1) (line "Each MODE is of the form…")
    `chmod #{future_file[:permissions]} #{dest}` if future_file[:permissions]
  end

  def replace_data(content)
    content.gsub(/\{\{(?<variable>[^}]+?)\}\}/) do |interpolation|
      variable = interpolation[2..-3]
      @data[variable.to_sym]
    end
  end

  def do_run(command, inside, environment, dry_run, quiet, verbose) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/ParameterLists
    indentation = "  " * @current_depth
    unless quiet
      puts "#{indentation}$ ".cyan.bold + command + (verbose ? " at #{inside.relative_path_from(@root_directory)}".light_blue + " with ".light_black + (format_environment_hash environment) : "")
    end

    return if dry_run

    stdout, stdout_w = IO.pipe
    stderr, stderr_w = IO.pipe

    system environment, command, { chdir: inside.to_s, out: stdout_w, err: stderr_w }
    stdout_w.close
    stderr_w.close

    stdout.read.each_line(chomp: true) do |line|
      puts "  #{indentation}#{line}"
    end
    stderr.read.each_line(chomp: true) do |line|
      puts "  #{indentation}#{line.red}"
    end
  end

  def format_environment_hash(environment)
    "{ ".light_black + (environment.map do |key, value|
      "$#{key}".red + "=".light_black + "\"#{value}\"".green
    end.join ", ".light_black) + " }".light_black
  end
end

def dedent(text) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
  lines = text.split "\n"
  return text if lines.empty?

  indents = lines.map do |line|
    if line =~ /\S/
      line.start_with?(" ") ? line.match(/^ +/).offset(0)[1] : 0
    end
  end
  indents.compact!
  if indents.empty?
    # No lines had any non-whitespace characters.
    return ([""] * lines.size).join "\n"
  end

  min_indent = indents.min
  return text if min_indent.zero?

  lines.map { |line| line =~ /\S/ ? line.gsub(/^ {#{min_indent}}/, "") : line }.join "\n"
end

def ensure_final_newline(text)
  if text.end_with? "\n"
    text
  else
    "#{text}\n"
  end
end

def capture_output
  old_stdout = $stdout
  old_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
  [$stdout.string, $stderr.string]
ensure
  $stdout = old_stdout
  $stderr = old_stderr
end
