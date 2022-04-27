require "colorize"
require "set"
require "shellwords"
require "yaml"

PERMISSIONS_PATTERN = /[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=]?[0-7]+/

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
    @current_depth = -1
    @to_write = [] # [ { :path, :content, :permissions } ]
  end

  def from_relative_to_root(path)
    @root_directory / path
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

  def preprocess
    process_front_matter
    strip_comments
    desugar
    process_includes
    # TODO process_see
    process_for
    process_if
    store_writes
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
      elsif /^(?<filename>.+?)\s*(\s+\((?<permissions>#{PERMISSIONS_PATTERN.to_s})\))?\s*\[$/.match line.strip
        output << "WRITE #{$~[:filename]} " + ($~[:permissions] ? "MODE #{$~[:permissions]}" : "") + " {"
        inside_write_directive_shorthand = true
      else
        output << line
      end
    end
    @document = output.join "\n"
  end

  def strip_comments
    output = []
    @document.lines(chomp: true).each_with_index do |line, index|
      if /^(?<content>.*)#\s.*$/ =~ line
        output << content
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

  def store_writes
    output = []
    current = {}
    inside_write_directive = -> { !current.keys.empty? }

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      if inside_write_directive.()
        if line.strip == "}"
          @to_write << current
          current = {}
        else
          current[:content] += line + "\n"
        end
      elsif /^WRITE(\s+INTO)?\s+(?<destination>.+?)(?:\s+MODE\s+(?<permissions>.+?))?\s*\{$/.match line.strip
        current = $~.named_captures.transform_keys(&:to_sym)
        current[:content] = ""
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
        output << "RUN install -D \"$DOCUMENT_DIR/#{$~[:source]}\" #{($~[:destination] || $~[:source]).shellescape}" + (if $~[:permissions]
          " -m #{$~[:permissions].shellescape}"
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

  def execute_writes(dry_run, quiet)
    @to_write.each do |future_file|
      do_write future_file, dry_run, quiet
    end
  end

  def walk(dry_run, quiet, verbose)
    current_path = [@root_directory]
    current_path_as_pathname = -> { current_path.reduce(Pathname.new "") { |path, fragment| path.join fragment } }
    @data[:HERE] = @root_directory

    @document.lines(chomp: true).each_with_index do |line, index|
      @current_line = index + 1
      @current_depth = current_path.length - 1

      @data.each do |key, value|
        line = line.gsub "{{#{key}}}", value.to_s
      end

      if /^(?<leaf>.+?)\s+\{/ =~ line.strip
        current_path << leaf
        @data[:HERE] = current_path_as_pathname.()
        if verbose
          puts "currenly #{current_path.map {|fragment| fragment.to_s }.join ' -> '}".light_black
        end
        do_mkpath current_location, dry_run, quiet
      elsif line.strip == "}"
        current_path.pop
        @data[:HERE] = current_path_as_pathname.()
        if verbose
          puts "currenly #{current_path.map {|fragment| fragment.to_s }.join ' -> '}".light_black
        end
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

    @current_depth = 0
    # TODO do writes alongside other operations
    puts ("Writing files " + "─" * 40).light_black
    execute_writes dry_run, quiet
  end

  def do_mkpath(path, dry_run, quiet)
    unless quiet
      puts "#{"  " * @current_depth}+ ".cyan.bold + path.relative_path_from(@root_directory).to_s
    end
    unless dry_run
      path.mkpath
    end
  end

  def do_write(future_file, dry_run, quiet)
    dest = from_relative_to_root future_file[:destination]
    do_mkpath dest.parent, dry_run, quiet

    unless quiet
      puts "> ".cyan.bold + dest.relative_path_from(@root_directory).to_s + (future_file[:permissions] ? " mode #{future_file[:permissions]}".yellow : "")
    end
    unless dry_run
      dest.write future_file[:content]
      # Not using dest.chmod as the syntax for permissions is more than just integers,
      # and matches in fact the exact syntax of chmod's argument, per the manpage, chmod(1) (line "Each MODE is of the form…")
      `chmod #{future_file[:permissions]} #{dest}` if future_file[:permissions]
    end
  end

  def do_run(command, inside, environment, dry_run, quiet, verbose)
    indentation = "  " * @current_depth
    unless quiet
      puts "#{indentation}$ ".cyan.bold + command + (verbose ? " at #{inside.relative_path_from(@root_directory)}".light_blue + " with ".light_black + (format_environment_hash environment) : "")
    end
    unless dry_run
      stdout, stdout_w = IO.pipe
      stderr, stderr_w = IO.pipe

      system environment, command, { :chdir => inside.to_s, :out => stdout_w, :err => stderr_w }
      stdout_w.close
      stderr_w.close

      stdout.read.each_line(chomp: true) do |line|
        puts "  " + indentation + line
      end
      stderr.read.each_line(chomp: true) do |line|
        puts "  " + indentation + line.red
      end
    end
  end

  def format_environment_hash(environment)
    "{ ".light_black + (environment.map do |key, value|
      "$#{key}".red + "=".light_black + "\"#{value}\"".green
    end.join ", ".light_black) + " }".light_black
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

def capture_output
  old_stdout = $stdout
  old_stderr = $stderr
  $stdout = StringIO.new
  $stderr = StringIO.new
  yield
  return $stdout.string, $stderr.string
ensure
  $stdout = old_stdout
  $stderr = old_stderr
end
