
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

  def if_equal other, compare=:==
    if block_given? && self.__send__(compare, other)
      yield self, other
    else
      self
    end
  end

  def if_truthy
    if self
      yield self
    else
      self
    end
  end
end

require_relative './buildin_data'

def lexer text
  Scanner.exec(text).map{|str| Token[str]}
end

class Scanner
  attr_reader :tokens

  def self.exec text
    new(text).tokens
  end

  def initialize text
    @tokens = sift_string("[cascade " + text + "]") do |it|
      sift_delimiter replace it
    end
  end

  private

  def sift_string text
    text.split("'").map.with_index do |chars, index|
      index.even? ? yield(chars) : "'" + chars + "'"
    end.flatten
  end

  # ３文字デリミタなどはStringと同じように予め分割しておくことにした
  # ３文字デリミタで分割した後に２文字デリミタで分割して……

  def sift_delimiter text
    return text if /\A'.*'\z/ === text
    tokens = []
    token = ""
    text.each_char do |c|
      case c
      when /\s/
        # Do not use these delimiters.
        tokens << token unless token == ""
        token = ""
      when '[', ']'
        # Use these delimiters.
        tokens << token unless token == ""
        tokens << c
        token = ""
      else
        token += c
      end
    end
    tokens
  end

  def replace text
    BUILDIN::REPLACE_SYMBOLS.each do |reg, str|
      text.gsub! reg, str
    end
    text
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
      @symbol = symbol.to_sym
    when ']'
      @type = ApplyEnd
      @symbol = symbol.to_sym
    else
      @type = Fanction
      @symbol = symbol.to_sym
    end
    self.freeze
  end

  def eval
    # Syntaxのevalをここに持ってくる必要があるかも
    # つうかリテラルを導入してしまった方がヨサゲ
    if it = CaseFunction.instance[@symbol.to_s]
      it[@symbol]
    else
      SpaceManager.instance[@symbol]
    end
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
    tokens.each do |token|
      if token.apply_start?
        new_syntax = BracketsSyntax.new @current
        @current.add new_syntax if !@current.nil?
        @root ||= new_syntax
        @current = new_syntax

      elsif token.fanction?
        @current.add token

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

  class SyntaxBase
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

  class BracketsSyntax < SyntaxBase
    attr_reader :nodes, :incomplete_syntax
    def self.[] *input
      new *input
    end

    def initialize syntax=nil
      @incomplete_syntax = syntax
      @nodes = []
    end

    def add symbol
      @nodes << symbol
    end

    def operator
      @nodes.first
    end

    def args
      @nodes[1..-1] || []
    end

    def eval
      if it = BUILDIN::SYNTAX_EVALUTES[operator.symbol]
        # syntax
        it[*@nodes]
      elsif it = CaseFunction.instance[operator.symbol.to_s]
        # case function
        it[operator.symbol, *@nodes.map(&:eval)]
      elsif immediate?
        # data
        SpaceManager.instance[operator.symbol]
      else
        # apply
        SpaceManager.instance[operator.symbol][*args.map(&:eval)]
      end
    end

    def immediate?
      args.empty?
    end

    def to_code
      @nodes.one? ? @nodes.first.inspect : "[#{@nodes.map(&:inspect).join(" ")}]"
    end
  end
end

class Space
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

  # def copy space, *symbols
  #   copy_functions ={}
  #   symbols.each do |s|
  #     copy_functions[s] = space[s]
  #   end
  #   @functions.update copy_functions
  # end
end

class SpaceManager
  include Singleton

  def initialize
    @history = []
    @current = Space.new
  end

  def new
    @history << @current
    @current = Space.new
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
    @current[symbol] || BUILDIN::FUNCTIONS[symbol] || raise("#{symbol} is undefined in space.")
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
    {Q: "(1 2 3)", A: [1,2,3]},

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
    {Q: "[set 'x' 1] [space [set 'x' 2] x] x", A: 1},

    # 無名関数
    # lambda
    {Q: "[lambda ('x' 'y') [+ x y]]", A: SAFE},
    {Q: "[bind 'z' [lambda ('x' 'y') [+ x y]]] [z 1 2]", A: 3},
    {Q: "[bind 'x' [lambda () 10]] x", A: 10},
    # {Q: "[[lambda [list 'x' 'y'] [+ x y]] 1 2]", A: 3},

    # if
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
question_and_answer
