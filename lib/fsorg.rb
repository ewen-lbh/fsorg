require "docopt"
require "colorize"
require "set"
require "shellwords"
require "yaml"

PERMISSIONS_PATTERN = /[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+/

def d(thing)
  p thing
  return thing
end

class Fsorg
  attr_accessor :data, :document, :document_path, :root_directory

  def initialize(root_directory, data, document, absolute_path)
    @root_directory = root_directory
    @shell = "/usr/bin/env bash"
    @document_path = absolute_path
    @data = { :HERE => @root_directory.to_s }.merge data
    @document = document
    @current_line = 0
  end

  def relative_to_root(path)
    File.join(@root_directory, path)
  end

  def depth_change(line)
    change = 0
    if /\}$/ =~ line
      change -= 1
    end
    if /^\{/ =~ line
      change += 1
    end
    change
  end

  def self.from_command_line
    args = Docopt.docopt <<-DOC
      Usage:
          fsorg [options] <filepath>
          fsorg [options] <data> <filepath>

      Options:
          -h --help                 Show this screen.
          -v --version              Show version.
          -r --root=ROOT_DIRECTORY  Set the root directory.
    DOC

    filepath = Pathname.new args["<filepath>"]
    document = File.new(filepath).read.strip
    data_raw = args["<data>"] || "{}"
    data = YAML.load data_raw, symbolize_names: true
    root_directory = Pathname.new(args["--root"] || "")

    return Fsorg.new root_directory, data, document, Pathname.new(Dir.pwd).join(filepath)
  end

  def preprocess
    process_front_matter
    desugar
    process_includes
    # TODO process_see
    process_for
    process_if
    turn_writes_into_runs
    turn_puts_into_runs
    ask_missing_variables
    process_root
    process_shell
  end

  def process_front_matter
    unless /^-+$/ =~ @document.lines(chomp: true).first
      return
    end

    # Remove front matter from document
    front_matter_raw, rest = "", ""
    inside_front_matter = false
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_linecur = index + 1
      if /^-+$/ =~ line
        inside_front_matter = !inside_front_matter
        next
      end

      if inside_front_matter
        front_matter_raw += line + "\n"
      else
        rest += line + "\n"
      end
    end

    front_matter = YAML.load(front_matter_raw, symbolize_names: true) or {}

    @data = front_matter.merge @data
    @document = rest
  end

  def desugar
    output = []
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if /^\}(\s*ELSE\s*\{)$/.match line
        output << "}"
        output << $~[1]
      elsif /^(\s*[^{]+?\{)([^{]+?)\}$/.match line.strip
        output << $~[1]
        output << $~[2]
        output << "}"
      else
        output << line
      end
    end
    @document = output.join "\n"
  end

  def process_includes
    output = []

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if line.start_with? "INCLUDE "
        filepath = @document_path.parent.join(line.sub /^INCLUDE /, "")
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

  def turn_writes_into_runs
    output = []
    inside_write_directive = false
    compact = nil
    current_content = []
    destination = nil
    permissions = nil

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_write_directive
        if line.strip == (compact ? "]" : "}")
          inside_write_directive = false
          content = deindent(current_content.join("\n")).gsub "\n", '\n'
          content = content.shellescape.gsub('\{\{', "{{").gsub('\}\}', "}}")
          output << "RUN" + (destination.include?("/") ? "mkdir -p #{Pathname.new(destination.strip).parent.to_s.shellescape}" : "") + "echo -ne #{content} > #{destination.strip.shellescape}" + (permissions ? " && chmod #{permissions} #{destination.strip.shellescape}" : "")
        else
          current_content << line
        end
      elsif /^WRITE(\s+INTO)?\s+(?<destination>.+?)(?:\s+MODE\s+(?<permissions>.+?))?\s*\{$/ =~ line.strip
        inside_write_directive = true
        compact = false
      elsif /^(?<destination>.+)(\s*\((?<permissions>#{PERMISSIONS_PATTERN})\))?\s*\[$/ =~ line.strip
        # Shouldn't be needed, as =~ should assign to destination, but heh, it doesn't work for some reason ¯\_(ツ)_/¯
        if destination.nil?
          destination = $~[:destination]
        end
        inside_write_directive = true
        compact = true
      else
        output << line
      end
    end

    @document = output.join "\n"
  end

  def turn_puts_into_runs
    output = []
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if /^PUT\s+(?<source>.+?)(\s+AS\s+(?<destination>.+?))?(\s+MODE\s+(?<permissions>.+?))?$/.match(line.strip)
        output << "RUN install -D \"$FSORG_ROOT/#{$~[:source]}\" #{($~[:destination] || $~[:source]).shellescape}" + (if $~[:permissions]
          " -D #{$~[:permissions].shellescape}"
        else
          ""
        end)
      else
        output << line
      end
    end

    @document = output.join "\n"
  end

  def process_for
    output = []
    inside_for_directive = false
    body = []
    args = nil
    current_depth = 0
    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_for_directive
        current_depth += depth_change line.strip
        if current_depth == 0
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

  def repeat_for_each(iteratee, iterator, directives)
    output = []
    unless data[iterator.to_sym]
      raise "[#{@document_path}:#{@current_line}]".colorize :red + "Variable '#{iterator}' not found (iterators cannot be asked for interactively). Available variables at this point: #{data.keys.join(", ")}."
    end
    unless data[iterator.to_sym].is_a? Array
      raise "[#{@document_path}:#{@current_line}]".colorize :red + "Cannot iterate over '#{iterator}', which is of type #{data[iterator.to_sym].class}."
    end
    data[iterator.to_sym].each do |item|
      output += directives.map do |directive|
        directive.gsub "{{#{iteratee}}}", item.to_s
      end
    end
    output
  end

  def process_if
    output = []
    inside_if = false
    body_if = []
    inside_else = false
    body_else = []
    current_condition = nil
    current_depth = 0

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_if
        current_depth += depth_change line.strip
        if current_depth == 0
          inside_if = false
          inside_else = false
          output += body_if if evaluates_to_true? current_condition
        else
          body_if << line
        end
      elsif inside_else
        current_depth += depth_change line.strip
        if current_depth == 0
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
        if current_condition.nil?
          raise "[#{@document_path}:#{@current_line}] Cannot use ELSE without IF."
        end
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
    unless @data.include? condition.to_sym
      raise "[#{@document_path}:#{@current_line}] Variable '#{condition}' not found. Available variables at this point: #{data.keys.join(", ")}."
    end

    @data[condition.to_sym]
  end

  def ask_missing_variables
    @document.scan /\{\{(?<variable>[^}]+?)\}\}/ do |variable|
      unless @data.include? variable[0].to_sym
        @data[variable[0].to_sym] = :ask
      end
    end

    @data.each do |key, value|
      if value == :ask
        print "#{key}? "
        @data[key] = YAML.load STDIN.gets.chomp
      end
    end
  end

  def process_root
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

  def walk
    current_path = [@root_directory]
    current_path_as_pathname = -> { current_path.reduce(Pathname.new "") { |path, fragment| path.join fragment } }
    @data[:HERE] = @root_directory

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      
      @data.each do |key, value|
        line = line.gsub "{{#{key}}}", value.to_s
      end

      if /^RUN\s+(?<command>.+?)$/ =~ line.strip
        puts "run ".colorize(:cyan) + command + " at ".colorize(:blue) + current_location.to_s.colorize(:blue)
      elsif line.strip == "}"
        current_path.pop
      elsif /^(?<leaf>.+?)\s+\{/ =~ line.strip
        current_path << leaf
        @data[:HERE] = current_path_as_pathname.()
        puts "mk  ".colorize(:cyan) + current_location.to_s
      end
    end
  end
end

def deindent(text)
  using_tabs = text.lines(chomp: true).any? { |line| /^\t/ =~ line }
  indenting_with = using_tabs ? "\t" : " "
  depth = text.lines.map do |line|
    count = 0
    until line[count] != indenting_with
      count += 1
    end
    count
  end.min
  pattern = /^#{using_tabs ? '\t' : " "}{#{depth}}/

  text.lines(chomp: true).map do |line|
    line.sub pattern, ""
  end.join "\n"
end
