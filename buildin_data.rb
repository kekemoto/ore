
module BUILDIN
  SYNTAX_EVALUTES = {}

  CASE_FUNCTIONS = [
    # Number literal
    [/\A[+|-]?[0-9]+.?[0-9]*\z/, ->(symbol, *args){symbol.to_f}],

    # String literal
    [/\A'.*'\z/, ->(symbol, *args){symbol[1...-1]}],
  ]

  FUNCTIONS = {
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
end
