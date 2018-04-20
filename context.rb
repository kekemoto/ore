
class Context
  def initialize hash={}
    @hash = hash.with_indifferent_access
  end

  def [] symbol
    @hash[symbol]
  end

  def []= symbol, proc
    @hash[symbol] = proc
  end

  def key? symbol
    @hash.key? symbol
  end
end

class ContextManager
  include Singleton

  def initialize
    @history = []
    @current = Context.new
  end

  def make
    @history << @current
    @current = Context.new
  end

  def back
    @current = @history.pop
  end

  def [] symbol
    @current[symbol] || $buildin_functions[symbol] || raise("#{symbol} is undefined in context.")
  end

  def []= symbol, proc
    @current[symbol] = proc
  end

  def key? symbol
    @current.key? symbol
  end
end

$case_functions = [
  # Number literal
  [/\A[+|-]?[0-9]+.?[0-9]*\z/, ->(symbol, *args){symbol.to_f}],

  # String literal
  [/\A'.*'\z/, ->(symbol, *args){symbol[1...-1]}],
]

$buildin_functions = {
  define: ->(symbol, proc){
    ContextManager.instance[symbol] = proc
  },

  set: ->(symbol, value){
    ContextManager.instance[symbol] = ->(){value}
  },

  define?: ->(symbol){
    ContextManager.instance.key? symbol
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
