
module BUILDIN
  SYNTAX_EVALUTES = {
    # [coroutice [+ 1 2]]
    coroutine: ->(syntaxes){
      ->(){
        syntaxes.map(&:eval).last
      }
    },

    context: ->(syntaxes){
      ContextManager.instance.make
      syntaxes.map(&:eval)
      ContextManager.instance.back
    },

    # [lambda [list 'x'] [+ 1 x]]
    lambda: ->(syntaxes){
      args = syntaxes.shift.eval
      body = syntaxes.map(&:to_code)

      Kernel.eval <<~DOC
        ->(#{args.join(',')}){
          ContextManager.instance[:eval]["
            #{args.map{|arg| "[set '#{arg}' \#{#{arg}}]"}.join(' ')}
            #{body.join(' ')}
          "]
        }
      DOC
    },
  }.with_indifferent_access

  CASE_FUNCTIONS = [
    # Number literal
    [/\A[+|-]?[0-9]+.?[0-9]*\z/, ->(symbol, *args){symbol.to_f}],

    # String literal
    [/\A'.*'\z/, ->(symbol, *args){symbol[1...-1]}],
  ]

  FUNCTIONS = {
    bind: ->(symbol, proc){
      ContextManager.instance[symbol] = proc
    },

    set: ->(symbol, value){
      ContextManager.instance[symbol] = ->(){value}
    },

    bind?: ->(symbol){
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
      AST.make(lexer str).eval
    },
  }.with_indifferent_access
end
