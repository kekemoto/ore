
require 'pp'
require 'singleton'
require 'active_support/inflector'
require 'active_support/core_ext/hash/indifferent_access'

def lexer text
  Scanner[text].map{|code| Token[code]}
end

class Scanner
  attr_reader :tokens

  def self.[] text
    new(text).tokens
  end

  def initialize text
    @state = :normal
    @tokens = []
    @token = ''
    "[cascade #{text}]".each_char do |char|
      screen char
    end
  end

  private

  def screen char
    case @state
    when :normal
      case char
      when Delimiter::NORMAL
        @tokens << @token unless @token == ''
        @token = ''
      when Delimiter::FUNCTION
        @tokens << @token unless @token == ''
        @tokens << char
        @token = ''
      when Delimiter::STRING
        @token += char
        @state = :string
      else
        @token += char
      end

    when :string
      case char
      when Delimiter::STRING
        @token += char
        @state = :normal
      else
        @token += char
      end

    else
      raise "#{@state} is not implemented in scan state."
    end
  end

  module Delimiter
    # space
    NORMAL = /\s/
    # [ ]
    FUNCTION = /(\[|\])/
    # '
    STRING = /'/
  end
end

class Token
  attr_reader :code, :type

  ApplyStart = :ApplyStart
  ApplyEnd = :ApplyEnd
  Fanction = :Fanction

  def self.[] code
    new code
  end

  def initialize code
    case code
    when '['
      @type = ApplyStart
      @code = code
    when ']'
      @type = ApplyEnd
      @code = code
    else
      @type = Fanction
      @code = code
    end
    self.freeze
  end

  [ApplyStart, ApplyEnd, Fanction].each do |t|
    define_method "#{t.to_s.underscore}?", ->(){
      Kernel.eval "#{@type} == #{t}"
    }
  end

  def inspect
    "<#{@code}:#{@type}>"
  end
end

class SyntaxTree
  def self.[] literals
    new literals
  end

  def initialize literals
    enum = literals.to_enum
    loop do
      li = enum.next
      if li.apply_start?
        new_syntax = Function[enum.next, @current]
        @current.add new_syntax if !@current.nil?
        @root ||= new_syntax
        @current = new_syntax
      elsif li.fanction?
        @current.add Function[li]
      elsif li.apply_end?
        @current = @current.incomplete_syntax
      else
        raise "Not implemented literal type : #{li.type}"
      end
    end
  end

  def eval
    @root.eval
  end

  def inspect
    @root.inspect
  end

  class BracketsSyntax
    attr_reader :operator, :edges, :incomplete_syntax
    def self.[] *input
      new *input
    end

    def initialize literal=nil, syntax=nil
      @operator = literal
      @edges = []
      @incomplete_syntax = syntax
    end

    def add function
      @edges << function
    end

    def immediate?
      @edges.empty?
    end

    def eval
      raise 'Overwrite required'
    end

    def inspect
      immediate? ? "[#{@operator.code}]" : "[#{@operator.code} #{@edges.map(&:inspect).join(' ')}]"
    end
  end

  class Function < BracketsSyntax
    def eval
      $case_function_space.each do |(rule, lambda)|
        return lambda[@operator.code, *@edges.map(&:eval)] if rule === @operator.code
      end
      $function_space[@operator.code][*@edges.map(&:eval)]
    end
  end
end

$case_function_space = [
  # Number literal
  [/\A[+|-]?[0-9]+.?[0-9]*\z/, ->(code, *args){code.to_f}],

  # String literal
  [/\A'.*'\z/, ->(code, *args){code[1...-1]}],
]

$function_space = {
  set: ->(code, proc){
    $function_space[code] = proc
  },

  setv: ->(code, value){
    $function_space[code] = ->(){value}
  },

  defined?: ->(code){
    $function_space.key? code
  },

  undefined?: ->(code){
    not $function_space.key? code
  },

  cascade: ->(*results){
    results.last
  },

  true: ->(){true},

  false: ->(){false},

  nil: ->(){nil},

  '+' => ->(*numbers){
    raise "#{__method__} function is make one or more arguments." if numbers.size < 1
    numbers.reduce(0){|acm, num| acm + num}
  },

  '-' => ->(*numbers){
    raise "#{__method__} function is make two or more arguments." if numbers.size < 2
    numbers.reduce{|acm, num| acm - num}
  },

  '*' => ->(*numbers){
    numbers.reduce(1){|acm, num| acm * num}
  },

  '/' => ->(*numbers){
    raise "#{__method__} function is make two or more arguments." if numbers.size < 2
    numbers.reduce{|acm, num| acm / num}
  },

  list: ->(*input){
    [*input]
  },

  eval: ->(str){
    SyntaxTree[lexer str].eval
  },

  lambda: ->(args, body){
    eval <<~END
      ->(#{args.join(',')}){
        $function_space[:eval]["
          #{args.map{|arg| "[setv '#{arg}' \#{#{arg}}]"}.join(' ')}
          #{body}
        "]
      }
    END
  },
}.with_indifferent_access

$function_space.default_proc = ->(_, code){raise "#{code} is undefind in function_space."}

# class FunctionManager
#   class FunctionSpace
#     def initialize space=nil
#       @parent_space = space
#       @hash = {}.with_indifferent_access
#       @hash.default_proc = ->(_, code){raise "#{code} is undefind in function_space."}
#     end
#   end
# end

def run text
  SyntaxTree.new(lexer text).eval
end

def tree text
  pp SyntaxTree.new(lexer text);0
end

SAFE = :safe_is_sign_as_a_nothing_error
def question_and_answer
  tests = [
    # データ
    # Data
    {Q: "1", A: 1},
    {Q: "'string'", A: "string"},
    {Q: "true", A: true},
    {Q: "false", A: false},
    {Q: "nil", A: nil},
    {Q: "[list 1 2 3]", A: [1,2,3]},

    # 四則演算
    # Arithmetic operations
    {Q: "[+ 1 10 100]", A: 111},
    {Q: "[- 1 10 100]", A: -109},
    {Q: "[* 2 3 4 5]", A: 120},
    {Q: "[/ 6 3 2]", A: 1},

    # 変数の代入
    # Variable assignments
    {Q: "[setv 'x' 1]", A: SAFE},
    {Q: "[setv 'x' [list 1 2 3]] x", A: [1,2,3]},

    # 手続き的な実行
    # Procedural execution
    {Q: "[cascade [setv 'x' 3] x]", A: 3},

    # 構文テスト
    # syntax test
    {Q: "[+ [+ 1 2] [+ 3 4]]", A: 10},
    {Q: "[+ [1] [2]]", A: 3},
    {Q: "1 [+ 5 4] 3", A: 3},

    # eval
    {Q: "[eval '[+ 1 2]']", A: 3},

    # lambda
    {Q: "[lambda [list 'x' 'y'] '[+ x y]']", A: SAFE},
    {Q: "[set 'z' [lambda [list 'x' 'y'] '[+ x y]']] [z 1 2]", A: 3},
    {Q: "[set 'x' [lambda [list] '10']] x", A: 10},

    # {Q: "[dot Hash new]", A: {}},
    # {Q: "[dot [dot Hash new] store 'a' 1]", A: {'a' => 1}},
  ]

  tests.each do |test|
    if test[:A] == SAFE
      run(test[:Q])
    else
      raise test[:Q] unless run(test[:Q]) == test[:A]
    end
  end
  puts "OK!"
end
question_and_answer
