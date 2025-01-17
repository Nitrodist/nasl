###############################################################################
# Copyright (c) 2011, Mak Kolybabi
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
################################################################################

module Nasl
  class TokenException < Exception
  end

  class Tokenizer
    @@initialized = false

    @@keywords = {
      'break'      => :BREAK,
      'continue'   => :CONTINUE,
      'else'       => :ELSE,
      'export'     => :EXPORT,
      'for'        => :FOR,
      'foreach'    => :FOREACH,
      'function'   => :FUNCTION,
      'global_var' => :GLOBAL,
      'if'         => :IF,
      'import'     => :IMPORT,
      'include'    => :INCLUDE,
      'local_var'  => :LOCAL,
      'repeat'     => :REPEAT,
      'return'     => :RETURN,
      'until'      => :UNTIL,
      'x'          => :REP,
      'while'      => :WHILE,

      'FALSE'      => :FALSE,
      'NULL'       => :UNDEF,
      'TRUE'       => :TRUE
    }

    @@operators = [
      ["><",   :SUBSTR_EQ],
      [">!<",  :SUBSTR_NE],

      ["=~",   :REGEX_EQ],
      ["!~",   :REGEX_NE],

      ["==",   :CMP_EQ],
      ["!=",   :CMP_NE],
      ["<=",   :CMP_LE],
      [">=",   :CMP_GE],

      ["=",    :ASS_EQ],
      ["+=",   :ADD_EQ],
      ["-=",   :SUB_EQ],
      ["*=",   :MUL_EQ],
      ["/=",   :DIV_EQ],
      ["%=",   :MOD_EQ],
      [">>=",  :SRL_EQ],
      [">>>=", :SRA_EQ],
      ["<<=",  :SLL_EQ],

      ["||",   :OR],
      ["&&",   :AND],
      ["!",    :NOT],

      ["|",    :BIT_OR],
      ["^",    :BIT_XOR],
      ["&",    :BIT_AND],
      [">>>",  :BIT_SRA],
      [">>",   :BIT_SRL],
      ["<<",   :BIT_SLL],

      ["<",    :CMP_LT],
      [">",    :CMP_GT],

      ["++",   :INCR],
      ["--",   :DECR],

      ["**",   :EXP],

      ["+",    :ADD],
      ["-",    :SUB],
      ["*",    :MUL],
      ["/",    :DIV],
      ["%",    :MOD],

      ["~",    :BIT_NOT],

      [".",    :PERIOD],
      [",",    :COMMA],
      [":",    :COLON],
      [";",    :SEMICOLON],
      ["(",    :LPAREN],
      [")",    :RPAREN],
      ["[",    :LBRACK],
      ["]",    :RBRACK],
      ["{",    :LBRACE],
      ["}",    :RBRACE]
    ]

    def initialize!
      return if @@initialized

      # Convert the operators into a regex-compatible form.
      @@operators = @@operators.map do |op, type|
        [Regexp.new("^#{Regexp.escape(op)}"), op, type]
      end

      @@initialized = true
    end

    def initialize(code, path)
      @code = code

      # Perform one-time initialization of tokenizer data structures.
      initialize!

      # Create a context object that will be shared amongst all tokens for this
      # code.
      @ctx = Context.new(@code, path)

      reset
    end

    def consume(num=1)
      # Update the index of the character we're currently looking at.
      @point += num

      # Update the flag that indicates whether we've reached the file's end.
      @eof = (@point >= @code.length)

      # Update the the character we're examining currently.
      @char = @code[@point]

      # Extract the remainder of the line.
      @line = @code[@point..@ctx.eol(@point)]
    end

    def reset
      # Set tokenizer to initial state, ready to tokenize the code from the
      # start.
      @point = 0
      consume(0)
      skip

      # Return tokenizer to allow method chaining.
      self
    end

    def skip
      while true do
        whitespace = @line[/^(\s+|\s*#.*$)/]
        return if whitespace.nil?
        consume(whitespace.length)
      end
    end

    def die(msg)
      # We want the default context for token errors to be all lines that
      # contain the region.
      region = @ctx.bol(@mark)..@ctx.eol(@point)
      bt = @ctx.context(@mark..@point + 1, region)

      # Raise an exception with the context as our backtrace.
      raise TokenException, msg, bt
    end

    def get_identifier
      # Identifiers are composed of letters, digits, and underscores.
      ident = @line[/^[_a-z][_a-z0-9]*/i]
      consume(ident.length)

      # Assume that we've got an identifier until proven otherwise.
      type = :IDENT

      # Identifiers may be prefixed with keywords. One example of a valid
      # identifier is "break_". To ensure that we catch these cases, we
      # initially parse all keywords as identifiers and then convert them as
      # needed.
      type = @@keywords[ident] if @@keywords.has_key? ident

      return [type, ident]
    end

    def get_integer
      # Try and parse the integer in any of three bases.
      if @line =~ /^0x/i
        # Hex integers start with "0x".
        type = :INT_HEX
        name = "hex"
        regex1 = /^0x\w+/i
        regex2 = /^0x[a-f0-9]+/i
      elsif @line =~ /^0\w+/
        # Octal integers start with "0".
        type = :INT_OCT
        name = "octal"
        regex1 = /^0\w+/
        regex2 = /^0[0-7]+/
      else
        # Anything else is a decimal integer.
        type = :INT_DEC
        name = "decimal"
        regex1 = /^\w*/
        regex2 = /^[0-9]+/
      end

      # First match with an overly permissive regex, and then match with the
      # proper regex. If the permissive and restrictive versions don't match,
      # then there's an error in the input.
      permissive = @line[regex1]
      restrictive = @line[regex2]

      if permissive.nil? || restrictive.nil? || permissive != restrictive
        # NASL interprets integers with a leading zero as octal if the only
        # contain octal digits, and considers the integers as decimal otherwise.
        type = :INT_DEC
        regex2 = /^[0-9]+/
        restrictive = @line[regex2]
      end

      if permissive.nil? || restrictive.nil? || permissive != restrictive
        die("Invalid #{name} literal")
      end

      # If there was no problem, we use the restrictive version as the body of
      # our integer.
      integer = restrictive

      consume(integer.length)

      return [type, integer]
    end

    def get_string
      unparsed = @code[@point..-1]

      if @char == "'"
        type = :DATA

        # Single-quoted strings cannot have single-quotes stuffed inside them.
        contents = unparsed[/\A'(\\.|[^'\\])*'/m]
        die("Unterminated single-quoted string") if contents.nil?
      else
        type = :STRING

        # Double-quoted strings cannot have double quotes stuffed inside them.
        contents = unparsed[/\A"[^"]*"/m]
        die("Unterminated double-quoted string") if contents.nil?
      end

      # Move the point forward over the string.
      consume(contents.length)

      # Remove the bounding quotes.
      contents = contents[1..-2]

      return [type, contents]
    end

    def get_operator
      # These are all of the operators defined in NASL. Their order is vitally
      # important.
      @@operators.each do |regex, op, type|
        next if @line !~ regex
        consume(op.length)
        return [type, op]
      end

      return nil
    end

    def get_token
      # Make sure we're not at the end of the file.
      return [false, Token.new(:EOF, "$", @point...@point, @ctx)] if @eof

      # Save our starting point, which to use Emacs terminology is called the
      # 'mark'.
      @mark = @point

      # Try to parse token at the point.
      token = if @char =~ /[_a-z]/i
        get_identifier
      elsif @char =~ /['"]/
        get_string
      elsif @char =~ /[0-9]/
        get_integer
      else
        get_operator
      end

      # Everything in the language is enumerated by the above functions, so if
      # we get here without a token parsed, the input file is invalid.
      die("Invalid character ('#@char')") if token.nil?
      skip

      return [token.first, Token.new(*token, @mark...@point, @ctx)]
    end

    def get_tokens
      tokens = []

      until @eof
        tokens << get_token
      end

      return tokens
    end
  end
end
