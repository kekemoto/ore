
require 'pp'
require 'singleton'
# require 'forwardable'
require 'active_support/inflector'
require 'active_support/core_ext/hash/indifferent_access'

class Object
  def tapp
    self.tap{|obj| pp obj}
  end

  def try method, *args
    if self.respond_to?(method)
      self.__send__(method, *args)
    else
      if block_given?
        yield self
      else
        nil
      end
    end
  end
end

require_relative './buildin_data'

def lexer text
  Scanner[text].map{|str| Token[str]}
end

# class Scanner
#   attr_reader :tokens
#
#   def self.[] text
#     new(text).tokens
#   end
#
#   def initialize text
#     @state = :normal
#     @tokens = []
#     @token = ''
#     "[cascade #{text}]".each_char do |char|
#       screen char
#     end
#   end
#
#   private
#
#   def screen char
#     case @state
#     when :normal
#       case char
#       when Delimiter::NORMAL
#         @tokens << @token unless @token == ''
#         @token = ''
#       when Delimiter::FUNCTION
#         @tokens << @token unless @token == ''
#         @tokens << char
#         @token = ''
#       when Delimiter::STRING
#         @token += char
#         @state = :string
#       else
#         @token += char
#       end
#
#     when :string
#       case char
#       when Delimiter::STRING
#         @token += char
#         @state = :normal
#       else
#         @token += char
#       end
#
#     else
#       raise "#{@state} is not implemented in scan state."
#     end
#   end
#
#   module Delimiter
#     # space
#     NORMAL = /\s/
#     # [ ]
#     FUNCTION = /(\[|\])/
#     # '
#     STRING = /'/
#   end
# end

class Scanner
  class Queue
    # This singleton class is QueueManager
    class << self
      attr_reader :dist

      def set
        @dist = (0..3).reduce(nil){|result, i| new i, result}
      end

      def enq input
        @dist.enq input
        self
      end

      def match? delimiter
        @dist.match? delimiter
      end

      def inspect
        @dist.inspect
      end
    end

    def initialize size=0, destination=nil
      @size = size
      @chars = []
      @destination = destination
    end

    def enq char
      return None if None == char
      if @size.zero?
        @chars.push char
        None
      elsif @chars.size < @size
        @chars.push char
        None
      else
        @chars.push char
        @destination.try :enq, @chars.shift
      end
    end

    def show
      @chars.join
    end

    def press result=""
      if @destination.nil?
        show + result
      else
        @destination.press show + result
      end
    end

    def match? delimiter
      if delimiter === show
        [@destination.press, show]
      else
        if @destination.nil?
          false
        else
          @destination.match? delimiter
        end
      end
    end

    def inspect
      if @destination.nil?
        "#{@size.inspect}:#{@chars.inspect}"
      else
        "#{@destination.inspect} <- #{@size.inspect}:#{@chars.inspect}"
      end
    end

    class None
    end
  end

  class Automaton
    def initialize
      @state = :normal
    end

    def check chars
      case @state
      when :normal
      end
    end
  end

  def initialize text

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

class AST
  def self.make tokens
    new tokens
  end

  def initialize tokens
    enum = tokens.to_enum
    loop do
      token = enum.next
      if token.apply_start?
        new_syntax = BracketsSyntax.new enum.next, @current
        @current.add new_syntax if !@current.nil?
        @root ||= new_syntax
        @current = new_syntax

      elsif token.fanction?
        @current.add BracketsSyntax.new token

      elsif token.apply_end?
        @current = @current.incomplete_syntax

      else
        raise "Not implemented token type : #{token.type}"
      end
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

    def eval
      BUILDIN::SYNTAX_EVALUTES[@operator.symbol].try(:call, *@edges) do
        # If "try" is used, "@edges.map(&:eval)" will be evaluated first.
        # So do not use "try"
        if it = CaseFunction.instance[@operator.symbol]
          it.call(@operator.symbol, *@edges.map(&:eval))
        else
          ContextManager.instance[@operator.symbol][*@edges.map(&:eval)]
        end
      end
    end

    def immediate?
      @edges.empty?
    end

    def to_code
      immediate? ? "#{@operator.symbol}" : "[#{@operator.symbol} #{@edges.map(&:inspect).join(' ')}]"
    end
  end
end

class Context
  def initialize functions={}
    @functions = functions.with_indifferent_access
  end

  def [] symbol
    @functions[symbol]
  end

  def []= symbol, proc
    @functions[symbol] = proc
  end

  def key? symbol
    @functions.key? symbol
  end

  # def copy context, *symbols
  #   copy_functions ={}
  #   symbols.each do |s|
  #     copy_functions[s] = context[s]
  #   end
  #   @functions.update copy_functions
  # end
end

class ContextManager
  include Singleton

  def initialize
    @history = []
    @current = Context.new
  end

  def new
    @history << @current
    @current = Context.new
  end

  def back
    @current = @history.pop
  end

  def make
    new
    result = yield
    back
    result
  end

  def [] symbol
    @current[symbol] || BUILDIN::FUNCTIONS[symbol] || raise("#{symbol} is undefined in context.")
  end

  def []= symbol, proc
    @current[symbol] = proc
  end

  def key? symbol
    @current.key? symbol
  end
end

class CaseFunction
  include Singleton

  def initialize
    @data = BUILDIN::CASE_FUNCTIONS
  end

  def [] symbol
    @data.find{|(rule, lambda)| rule === symbol}.try(:at, 1)
  end
end

def run text
  AST.make(lexer text).eval
end

def tree text
  pp AST.make(lexer text);0
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
    {Q: "[set 'x' 1]", A: SAFE},
    {Q: "[set 'x' 1] x", A: 1},
    {Q: "[set 'x' [list 1 2 3]] x", A: [1,2,3]},
    {Q: "[bind? 'qawsedrftgyhujikolp']", A: false},
    {Q: "[set 'x' 1] [bind? 'x']", A: true},

    # 手続き的な実行
    # Procedural execution
    {Q: "[cascade [set 'x' 3] x]", A: 3},

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
    {Q: "[bind 'x' [coroutine [+ 1 2]]] x", A: 3},
    {Q: "[bind 'x' [coroutine [+ 1 2]]] [+ x x]", A: 6},

    # スコープ
    # Scope
    {Q: "[set 'x' 1] [context [set 'x' 2] x] x", A: 1},

    # 無名関数
    # lambda
    {Q: "[lambda [list 'x' 'y'] [+ x y]]", A: SAFE},
    {Q: "[bind 'z' [lambda [list 'x' 'y'] [+ x y]]] [z 1 2]", A: 3},
    {Q: "[bind 'x' [lambda [list] 10]] x", A: 10},
    # {Q: "[[lambda [list 'x' 'y'] [+ x y]] 1 2]", A: 3},

    # if, for
    {Q: "[if true 1 2]", A: 1},
    {Q: "[if false 1 2]", A: 2},
  ]

  tests.each do |test|
    if test[:A] == SAFE
      run(test[:Q])
    else
      result = run(test[:Q])
      raise "TestError: Question:#{test[:Q]}, Result:#{result}, Answer:#{test[:A]}" unless result == test[:A]
    end
  end
  puts "OK!"
end
# question_and_answer
