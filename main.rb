
require 'pp'
require 'singleton'
require 'active_support/inflector'
require 'active_support/core_ext/hash/indifferent_access'

class Object
  def tapp
    self.tap{|obj| pp obj}
  end
end

def lexer text
  Scanner[text].map{|str| Token[str]}
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
  attr_reader :symbol, :type

  ApplyStart = :ApplyStart
  ApplyEnd = :ApplyEnd
  Fanction = :Fanction

  def self.[] symbol
    new symbol
  end

  def initialize symbol
    case symbol
    when '['
      @type = ApplyStart
      @symbol = symbol
    when ']'
      @type = ApplyEnd
      @symbol = symbol
    else
      @type = Fanction
      @symbol = symbol
    end
    self.freeze
  end

  [ApplyStart, ApplyEnd, Fanction].each do |t|
    define_method "#{t.to_s.underscore}?", ->(){
      Kernel.eval "#{@type} == #{t}"
    }
  end

  def inspect
    "<#{@symbol}:#{@type}>"
  end
end

class SyntaxTree
  def self.[] tokens
    new tokens
  end

  def initialize tokens
    enum = tokens.to_enum
    loop do
      token = enum.next
      if token.apply_start?
        new_syntax = screen(enum.next, @current)
        @current.add new_syntax if !@current.nil?
        @root ||= new_syntax
        @current = new_syntax

      elsif token.fanction?
        @current.add screen token

      elsif token.apply_end?
        @current = @current.incomplete_syntax

      else
        raise "Not implemented token type : #{token.type}"
      end
    end
  end

  def screen token, syntax=nil
    case token.symbol
    when "coroutine"
      DefineCoroutine.new token, syntax
    when "lambda"
      DefineLambda.new token, syntax
    else
      Function.new token, syntax
    end
  end

  def eval
    @root.eval
  end

  def inspect
    @root.inspect
  end

  class SyntaxInterface
    def eval
      raise 'Overwrite required'
    end

    def to_code
      raise 'Overwrite required'
    end

    def inspect
      to_code
    end
  end

  class BracketsSyntax < SyntaxInterface
    attr_reader :operator, :edges, :incomplete_syntax
    def self.[] *input
      new *input
    end

    def initialize token=nil, syntax=nil
      @operator = token
      @edges = []
      @incomplete_syntax = syntax
    end

    def add function
      @edges << function
    end

    def immediate?
      @edges.empty?
    end

    def to_code
      immediate? ? "[#{@operator.symbol}]" : "[#{@operator.symbol} #{@edges.map(&:inspect).join(' ')}]"
    end
  end

  class Function < BracketsSyntax
    def eval
      $case_function_space.each do |(rule, lambda)|
        return lambda[@operator.symbol, *@edges.map(&:eval)] if rule === @operator.symbol
      end
      FunctionManager[@operator.symbol][*@edges.map(&:eval)]
    end
  end

  class DefineCoroutine < BracketsSyntax
    # [coroutice [+ 1 2]]
    def eval
      ->(){
        @edges.map(&:eval).last
      }
    end
  end

  class DefineSpace < BracketsSyntax
    def eval

    end
  end

  class DefineLambda < BracketsSyntax
    # [lambda [list 'x'] [+ 1 x]]
    def eval
      args = @edges.shift.eval
      body = @edges.map(&:to_code)

      Kernel.eval <<~DOC
        ->(#{args.join(',')}){
          FunctionManager[:eval]["
            #{args.map{|arg| "[setv '#{arg}' \#{#{arg}}]"}.join(' ')}
            #{body.join(' ')}
          "]
        }
      DOC
    end
  end
end

$case_function_space = [
  # Number literal
  [/\A[+|-]?[0-9]+.?[0-9]*\z/, ->(symbol, *args){symbol.to_f}],

  # String literal
  [/\A'.*'\z/, ->(symbol, *args){symbol[1...-1]}],
]

class FunctionManager
  class FunctionSpace
    def initialize space, hash=nil
      @parent_space = space || {}
      @hash = hash || {}.with_indifferent_access
    end

    def [] symbol
      @hash[symbol] || @parent_space[symbol] || raise("#{symbol} is undefind in function_space.")
    end

    def []= symbol, value
      @hash[symbol] = value
    end
  end

  def self.root
    @@root
  end

  def self.current
    @@current
  end

  def self.[] symbol
    @@current[symbol]
  end

  def self.[]= symbol, value
    @@current[symbol] = value
  end

  def self.parent
    @@current = @@current.parent_space
  end

  def self.make
    @@current = FunctionSpace.new @@current
  end

  @@root = FunctionSpace.new(nil,
    {
      set: ->(symbol, proc){
        FunctionManager[symbol] = proc
      },

      setv: ->(symbol, value){
        FunctionManager[symbol] = ->(){value}
      },

      define?: ->(symbol){
        FunctionManager.define? symbol
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
    }.with_indifferent_access
  )

  @@current = @@root
end

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

    # 変数
    # Variable
    {Q: "[setv 'x' 1]", A: SAFE},
    {Q: "[setv 'x' 1] x", A: 1},
    {Q: "[setv 'x' [list 1 2 3]] x", A: [1,2,3]},

    # 手続き的な実行
    # Procedural execution
    {Q: "[cascade [setv 'x' 3] x]", A: 3},

    # 構文テスト
    # syntax test
    {Q: "[+ [+ 1 2] [+ 3 4]]", A: 10},
    {Q: "1 [+ 5 4] 3", A: 3},
    {Q: "[+ [1] [2]]", A: 3},
    # {Q: "[[+] [1] [2]]", A: 3},

    # eval
    {Q: "[eval '[+ 1 2]']", A: 3},

    # コルーチン
    # Coroutine
    {Q: "[set 'x' [coroutine [+ 1 2]]] x", A: 3},
    {Q: "[set 'x' [coroutine [+ 1 2]]] [+ x x]", A: 6},

    # スコープ
    # Scope
    # {Q: "[set 'x' 1] [space [set 'x' 2] x] x", A: 1}

    # 無名関数
    # lambda
    {Q: "[lambda [list 'x' 'y'] [+ x y]]", A: SAFE},
    {Q: "[set 'z' [lambda [list 'x' 'y'] [+ x y]]] [z 1 2]", A: 3},
    {Q: "[set 'x' [lambda [list] 10]] x", A: 10},
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
