/*
  new syntax:
    #foo and `foo	match the string object 'foo' (it's also accepted in my JS)
    'abc'		match the string object 'abc'
    'c'			match the string object 'c'
    ``abc''		match the sequence of string objects 'a', 'b', 'c'
    "abc"		token('abc')
    [1 2 3]		match the array object [1, 2, 3]
    foo(bar)		apply rule foo with argument bar
    -> ...		semantic actions written in JS (see OMetaParser's atomicHostExpr rule)
*/

/*
ometa M {
  number = number:n digit:d -> { n * 10 + d.digitValue() }
         | digit:d          -> { d.digitValue() }
}

translates to...

M = objectThatDelegatesTo(OMeta, {
  number: function() {
            return this._or(function() {
                              var n = this._apply("number"),
                                  d = this._apply("digit")
                              return n * 10 + d.digitValue()
                            },
                            function() {
                              var d = this._apply("digit")
                              return d.digitValue()
                            }
                           )
          }
})
M.matchAll("123456789", "number")
*/

// the failure exception

fail = { toString: function() { return "match failed" } }

// streams and memoization

function OMInputStream(hd, tl) {
  this.memo = { }
  this.lst  = tl.lst
  this.idx  = tl.idx
  this.hd   = hd
  this.tl   = tl
}
OMInputStream.prototype.head = function() { return this.hd }
OMInputStream.prototype.tail = function() { return this.tl }
OMInputStream.prototype.type = function() { return this.lst.constructor }
OMInputStream.prototype.upTo = function(that) {
  var r = [], curr = this
  while (curr != that) {
    r.push(curr.head())
    curr = curr.tail()
  }
  return this.type() == String ? r.join('') : r
}

function OMInputStreamEnd(lst, idx) {
  this.memo = { }
  this.lst = lst
  this.idx = idx
}
OMInputStreamEnd.prototype = objectThatDelegatesTo(OMInputStream.prototype)
OMInputStreamEnd.prototype.head = function() { throw fail }
OMInputStreamEnd.prototype.tail = function() { throw fail }

// This is necessary b/c in IE, you can't say "foo"[idx]
Array.prototype.at  = function(idx) { return this[idx] }
String.prototype.at = String.prototype.charAt

function ListOMInputStream(lst, idx) {
  this.memo = { }
  this.lst  = lst
  this.idx  = idx
  this.hd   = lst.at(idx)
}
ListOMInputStream.prototype = objectThatDelegatesTo(OMInputStream.prototype)
ListOMInputStream.prototype.head = function() { return this.hd }
ListOMInputStream.prototype.tail = function() { return this.tl || (this.tl = makeListOMInputStream(this.lst, this.idx + 1)) }

function makeListOMInputStream(lst, idx) { return new (idx < lst.length ? ListOMInputStream : OMInputStreamEnd)(lst, idx) }

Array.prototype.toOMInputStream  = function() { return makeListOMInputStream(this, 0) }
String.prototype.toOMInputStream = function() { return makeListOMInputStream(this, 0) }

function makeOMInputStreamProxy(target) {
  return objectThatDelegatesTo(target, {
    memo:   { },
    target: target,
    tl: undefined,
    tail:   function() { return this.tl || (this.tl = makeOMInputStreamProxy(target.tail())) }
  })
}

// Failer (i.e., that which makes things fail) is used to detect (direct) left recursion and memoize failures

function Failer() { }
Failer.prototype.used = false

// the OMeta "class" and basic functionality

OMeta = {
  _apply: function(rule) {
    var memoRec = this.input.memo[rule]
    if (memoRec == undefined) {
      var origInput = this.input,
          failer    = new Failer()
      if (this[rule] === undefined)
        throw 'tried to apply undefined rule "' + rule + '"'
      this.input.memo[rule] = failer
      if (!this[rule].call) {
        alert("hey");
      }
      this.input.memo[rule] = memoRec = {ans: this[rule].call(this), nextInput: this.input}
      if (failer.used) {
        var sentinel = this.input
        while (true) {
          try {
            this.input = origInput
            var ans = this[rule].call(this)
            if (this.input == sentinel)
              throw fail
            memoRec.ans       = ans
            memoRec.nextInput = this.input
          }
          catch (f) {
            if (f != fail)
              throw f
            break
          }
        }
      }
    }
    else if (memoRec instanceof Failer) {
      memoRec.used = true
      throw fail
    }
    this.input = memoRec.nextInput
    return memoRec.ans
  },

  // note: _applyWithArgs and _superApplyWithArgs are not memoized, so they can't be left-recursive
  _applyWithArgs: function(rule) {
    var ruleFn = this[rule]
    var ruleFnArity = ruleFn.length
    for (var idx = arguments.length - 1; idx >= ruleFnArity + 1; idx--) // prepend "extra" arguments in reverse order
      this._prependInput(arguments[idx])
    return ruleFnArity == 0 ?
             ruleFn.call(this) :
             ruleFn.apply(this, Array.prototype.slice.call(arguments, 1, ruleFnArity + 1))
  },
  _superApplyWithArgs: function(recv, rule) {
    var ruleFn = this[rule]
    var ruleFnArity = ruleFn.length
    for (var idx = arguments.length - 1; idx > ruleFnArity + 2; idx--) // prepend "extra" arguments in reverse order
      recv._prependInput(arguments[idx])
    return ruleFnArity == 0 ?
             ruleFn.call(recv) :
             ruleFn.apply(recv, Array.prototype.slice.call(arguments, 2, ruleFnArity + 2))
  },
  _prependInput: function(v) {
    this.input = new OMInputStream(v, this.input)
  },

  // if you want your grammar (and its subgrammars) to memoize parameterized rules, invoke this method on it:
  memoizeParameterizedRules: function() {
    this._prependInput = function(v) {
      var newInput
      if (isImmutable(v)) {
        newInput = this.input[getTag(v)]
        if (!newInput) {
          newInput = new OMInputStream(v, this.input)
          this.input[getTag(v)] = newInput
        }
      }
      else newInput = new OMInputStream(v, this.input)
      this.input = newInput
    }
    this._applyWithArgs = function(rule) {
      var ruleFnArity = this[rule].length
      for (var idx = arguments.length - 1; idx >= ruleFnArity + 1; idx--) // prepend "extra" arguments in reverse order
        this._prependInput(arguments[idx])
      return ruleFnArity == 0 ?
               this._apply(rule) :
               this[rule].apply(this, Array.prototype.slice.call(arguments, 1, ruleFnArity + 1))
    }
  },

  _pred: function(b) {
    if (b)
      return true
    throw fail
  },
  _not: function(x) {
    var origInput = this.input
    try { x.call(this) }
    catch (f) {
      if (f != fail)
        throw f
      this.input = origInput
      return true
    }
    throw fail
  },
  _lookahead: function(x) {
    var origInput = this.input,
        r         = x.call(this)
    this.input = origInput
    return r
  },
  _or: function() {
    var origInput = this.input
    for (var idx = 0; idx < arguments.length; idx++)
      try { this.input = origInput; return arguments[idx].call(this) }
      catch (f) {
        if (f != fail)
          throw f
      }
    throw fail
  },
  _xor: function(ruleName) {
    var origInput = this.input, idx = 1, newInput, ans
    while (idx < arguments.length) {
      try {
        this.input = origInput
        ans = arguments[idx].call(this)
        if (newInput)
          throw 'more than one choice matched by "exclusive-OR" in ' + ruleName
        newInput = this.input
      }
      catch (f) {
        if (f != fail)
          throw f
      }
      idx++
    }
    if (newInput) {
      this.input = newInput
      return ans
    }
    else
      throw fail
  },
  disableXORs: function() {
    this._xor = this._or
  },
  _opt: function(x) {
    var origInput = this.input, ans
    try { ans = x.call(this) }
    catch (f) {
      if (f != fail)
        throw f
      this.input = origInput
    }
    return ans
  },
  _many: function(x) {
    var ans = arguments[1] != undefined ? [arguments[1]] : []
    while (true) {
      var origInput = this.input
      try { ans.push(x.call(this)) }
      catch (f) {
        if (f != fail)
          throw f
        this.input = origInput
        break
      }
    }
    return ans
  },
  _many1: function(x) { return this._many(x, x.call(this)) },
  _form: function(x) {
    var v = this._apply("anything")
    if (!isSequenceable(v))
      throw fail
    var origInput = this.input
    this.input = v.toOMInputStream()
    var r = x.call(this)
    this._apply("end")
    this.input = origInput
    return v
  },
  _consumedBy: function(x) {
    var origInput = this.input
    x.call(this)
    return origInput.upTo(this.input)
  },
  _idxConsumedBy: function(x) {
    var origInput = this.input
    x.call(this)
    return {fromIdx: origInput.idx, toIdx: this.input.idx}
  },
  _interleave: function(mode1, part1, mode2, part2 /* ..., moden, partn */) {
    var currInput = this.input, ans = []
    for (var idx = 0; idx < arguments.length; idx += 2)
      ans[idx / 2] = (arguments[idx] == "*" || arguments[idx] == "+") ? [] : undefined
    while (true) {
      var idx = 0, allDone = true
      while (idx < arguments.length) {
        if (arguments[idx] != "0")
          try {
            this.input = currInput
            switch (arguments[idx]) {
              case "*": ans[idx / 2].push(arguments[idx + 1].call(this));                       break
              case "+": ans[idx / 2].push(arguments[idx + 1].call(this)); arguments[idx] = "*"; break
              case "?": ans[idx / 2] =    arguments[idx + 1].call(this);  arguments[idx] = "0"; break
              case "1": ans[idx / 2] =    arguments[idx + 1].call(this);  arguments[idx] = "0"; break
              default:  throw "invalid mode '" + arguments[idx] + "' in OMeta._interleave"
            }
            currInput = this.input
            break
          }
          catch (f) {
            if (f != fail)
              throw f
            // if this (failed) part's mode is "1" or "+", we're not done yet
            allDone = allDone && (arguments[idx] == "*" || arguments[idx] == "?")
          }
        idx += 2
      }
      if (idx == arguments.length) {
        if (allDone)
          return ans
        else
          throw fail
      }
    }
  },
  _currIdx: function() { return this.input.idx },

  // some basic rules
  anything: function() {
    var r = this.input.head()
    this.input = this.input.tail()
    return r
  },
  end: function() {
    return this._not(function() { return this._apply("anything") })
  },
  pos: function() {
    return this.input.idx
  },
  empty: function() { return true },
  apply: function(r) {
    return this._apply(r)
  },
  foreign: function(g, r) {
    var gi  = objectThatDelegatesTo(g, {input: makeOMInputStreamProxy(this.input)}),
        ans = gi._apply(r)
    this.input = gi.input.target
    return ans
  },

  //  some useful "derived" rules
  exactly: function(wanted) {
    if (wanted === this._apply("anything"))
      return wanted
    throw fail
  },
  "true": function() {
    var r = this._apply("anything")
    this._pred(r === true)
    return r
  },
  "false": function() {
    var r = this._apply("anything")
    this._pred(r === false)
    return r
  },
  "undefined": function() {
    var r = this._apply("anything")
    this._pred(r === undefined)
    return r
  },
  number: function() {
    var r = this._apply("anything")
    this._pred(typeof r === "number")
    return r
  },
  string: function() {
    var r = this._apply("anything")
    this._pred(typeof r === "string")
    return r
  },
  "char": function() {
    var r = this._apply("anything")
    this._pred(typeof r === "string" && r.length == 1)
    return r
  },
  space: function() {
    var r = this._apply("char")
    this._pred(r.charCodeAt(0) <= 32)
    return r
  },
  spaces: function() {
    return this._many(function() { return this._apply("space") })
  },
  digit: function() {
    var r = this._apply("char")
    this._pred(r >= "0" && r <= "9")
    return r
  },
  lower: function() {
    var r = this._apply("char")
    this._pred(r >= "a" && r <= "z")
    return r
  },
  upper: function() {
    var r = this._apply("char")
    this._pred(r >= "A" && r <= "Z")
    return r
  },
  letter: function() {
    return this._or(function() { return this._apply("lower") },
                    function() { return this._apply("upper") })
  },
  letterOrDigit: function() {
    return this._or(function() { return this._apply("letter") },
                    function() { return this._apply("digit")  })
  },
  firstAndRest: function(first, rest)  {
     return this._many(function() { return this._apply(rest) }, this._apply(first))
  },
  seq: function(xs) {
    for (var idx = 0; idx < xs.length; idx++)
      this._applyWithArgs("exactly", xs.at(idx))
    return xs
  },
  notLast: function(rule) {
    var r = this._apply(rule)
    this._lookahead(function() { return this._apply(rule) })
    return r
  },
  listOf: function(rule, delim) {
    return this._or(function() {
                      var r = this._apply(rule)
                      return this._many(function() {
                                          this._applyWithArgs("token", delim)
                                          return this._apply(rule)
                                        },
                                        r)
                    },
                    function() { return [] })
  },
  token: function(cs) {
    this._apply("spaces")
    return this._applyWithArgs("seq", cs)
  },
  fromTo: function (x, y) {
    return this._consumedBy(function() {
                              this._applyWithArgs("seq", x)
                              this._many(function() {
                                this._not(function() { this._applyWithArgs("seq", y) })
                                this._apply("char")
                              })
                              this._applyWithArgs("seq", y)
                            })
  },

  initialize: function() { },
  // match and matchAll are a grammar's "public interface"
  _genericMatch: function(input, rule, args, matchFailed) {
    if (args == undefined)
      args = []
    var realArgs = [rule]
    for (var idx = 0; idx < args.length; idx++)
      realArgs.push(args[idx])
    var m = objectThatDelegatesTo(this, {input: input})
    m.initialize()
    try { return realArgs.length == 1 ? m._apply.call(m, realArgs[0]) : m._applyWithArgs.apply(m, realArgs) }
    catch (f) {
      if (f == fail && matchFailed != undefined) {
        var input = m.input
        if (input.idx != undefined) {
          while (input.tl != undefined && input.tl.idx != undefined)
            input = input.tl
          input.idx--
        }
        return matchFailed(m, input.idx)
      }
      throw f
    }
  },
  match: function(obj, rule, args, matchFailed) {
    return this._genericMatch([obj].toOMInputStream(),    rule, args, matchFailed)
  },
  matchAll: function(listyObj, rule, args, matchFailed) {
    return this._genericMatch(listyObj.toOMInputStream(), rule, args, matchFailed)
  },
  createInstance: function() {
    var m = objectThatDelegatesTo(this)
    m.initialize()
    m.matchAll = function(listyObj, aRule) {
      this.input = listyObj.toOMInputStream()
      return this._apply(aRule)
    }
    return m
  }
}
