
module BUILDIN
  SYNTAX_EVALUTES = {
    # [coroutice [+ 1 2]]
    coroutine: ->(*syntaxes){
      ->(){
        syntaxes.map(&:eval).last
      }
    },

    context: ->(*syntaxes){
      ContextManager.instance.make do
        syntaxes.map(&:eval)
      end
    },

    # [lambda [list 'x' 'y'] [+ y x]]
    lambda: ->(*syntaxes){
      args = syntaxes.shift.eval
      body = syntaxes

      # ->(x,y){
      #   ContextManager.make do
      #     ContextManager.instance[:set]['x', x]
      #     ContextManager.instance[:set]['y', y]
      #     body.map(&:eval).last
      #   end
      # }
      Kernel.eval <<~DOC
        ->(#{args.join(',')}){
          ContextManager.instance.make do
            #{args.map{|arg|
              "ContextManager.instance[:set]['#{arg}', #{arg}]"
            }.join(';')}
            body.map(&:eval).last
          end
        }
      DOC
    },

    if: ->(bool, fun1, fun2=nil){
      if bool.eval
        fun1.eval
      else
        fun2.try :eval
      end
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
