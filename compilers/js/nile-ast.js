(function () {
  var String_toString_old = String.prototype.toString;
  String.prototype.toString = function()
  {
    if (!arguments[0])
      return String_toString_old.call(this);
    return String_toString_old.call(this) + "\n";
  };
  var Array_toString_old = Array.prototype.toString;
  Array.prototype.toString = function()
  {
    var col  = arguments[0];
    var col_ = col ? col + 4 : 0;
    var indentation  = Array(col).join(" ");
    var indentation_ = Array(col_).join(" ");
    var s = "[\n";
    if (!col)
      return Array_toString_old.call(this);
    for (var i = 0; i < this.length; i++) {
      s += indentation_;
      s += (this[i] == null ? "<null>\n" : this[i].toString(col_));
    }
    return s + indentation + "]\n";
  };
})();

nile.defineASTToString = function(name, fieldnames)
{
  return function() {
    var col  = arguments[0] || 0;
    var col_ = col + 4;
    var indentation  = Array(col).join(" ");
    var indentation_ = Array(col_).join(" ");
    var s = name + " {\n";
    for (var i = 0; i < fieldnames.length; i++) {
      var fieldvalue = this[fieldnames[i]];
      s += indentation_ + fieldnames[i] + "=";
      s += (fieldvalue == null           ) ? "<null>\n" :
           (typeof fieldvalue == "number") ? fieldvalue + "\n" :
           fieldvalue.toString(col_);
    }
    return s + indentation + "}\n";
  };
};

nile.defineASTResolve = function(fieldnames)
{
  return function(env) {
    var resolvedFields = [];
    for (var i = 0; i < fieldnames.length; i++) {
      var fieldname = fieldnames[i];
      var field     = this[fieldname];
      var resolvedField = (field == null         ) ? null :
                          (field instanceof Array) ? field.mapMethod('resolve', env) :
                                                     field.resolve(env);
      resolvedFields.push(resolvedField);
    }
    return this.prototype.constructor.apply(this, resolvedFields);
  };
};

nile.defineASTNode = function(name, fieldnames) {
  var nodeConstructor = function(fieldvalues) {
    for (var i = 0; i < fieldnames.length; i++)
      this[fieldnames[i]] = fieldvalues[i];
    return this;
  };
  var nodePrototype = function() { return new nodeConstructor(arguments); };
  nodeConstructor.prototype = nodePrototype;
  nodePrototype.toString = nile.defineASTToString(name, fieldnames);
  nodePrototype.resolve = nile.defineASTResolve(fieldnames);
  nile[name] = nodePrototype;
}

nile.defineASTNode("anytype",      []);
nile.defineASTNode("primtype",     []);
nile.defineASTNode("tupletype",    ["types"]);
nile.defineASTNode("recordtype",   ["fields"]);
nile.defineASTNode("processtype",  ["intype", "outtype"]);
nile.defineASTNode("typeref",      ["name"]);
nile.defineASTNode("vardecl",      ["name", "type"]);
nile.defineASTNode("tuplepat",     ["elements"]);
nile.defineASTNode("numexpr",      ["value"]);
nile.defineASTNode("varexpr",      ["var"]);
nile.defineASTNode("tupleexpr",    ["elements"]);
nile.defineASTNode("condcase",     ["value", "condition"]);
nile.defineASTNode("condexpr",     ["cases", "otherwise"]);
nile.defineASTNode("recfieldexpr", ["record", "field"]);
nile.defineASTNode("opexpr",       ["op", "fixity", "arg"]);
nile.defineASTNode("processinst",  ["processdef", "arg"]);
nile.defineASTNode("pipeline",     ["producer", "consumer"]);
nile.defineASTNode("vardef",       ["lvalue", "rvalue"]);
nile.defineASTNode("block",        ["vardefs", "stmts"]);
nile.defineASTNode("instmt",       ["values"]);
nile.defineASTNode("outstmt",      ["values"]);
nile.defineASTNode("ifstmt",       ["condition", "tblock", "fblock"]);
nile.defineASTNode("substmt",      ["pipeline"]);
nile.defineASTNode("typedef",      ["name", "type"]);
nile.defineASTNode("opsig",        ["name", "fixity", "param", "type"]);
nile.defineASTNode("opbody",       ["vardefs", "result"]);
nile.defineASTNode("opdef",        ["sig", "body"]);
nile.defineASTNode("processsig",   ["name", "param", "type"]);
nile.defineASTNode("processbody",  ["forpat", "block"]);
nile.defineASTNode("processdef",   ["sig", "prologue", "body", "epilogue"]);

nile.processdef.getName = function() { return this.sig.name; };
nile.typedef.getName    = function() { return this.name; };
nile.vardecl.getName    = function() { return this.name; };

nile.opexpr.isInfixRelational = function()
{
  return this.fixity == "in" && this.op &&
         "<>≤≥≠=≈≉".indexOf(this.op[0]) >= 0;
};

nile.opexpr.isChainedRelational = function()
{
  return this.isInfixRelational() &&
         this.arg.elements[0].prototype.constructor == nile.opexpr &&
         this.arg.elements[0].isInfixRelational();
};

nile.opexpr.unchainRelational = function()
{
  var arg1 = this.arg.elements[0];
  var arg2 = this.arg.elements[1];
  var aarg2 = arg1.arg[1];
  var arg2_ = nile.opexpr(this.op, this.fixity, [aarg2, arg2]);
  return nile.opexpr("∧", "in", [arg1, arg2_]);
};

nile.varexpr.splitVars = function()
{
  try {
    var node = NileParser.matchAll(this.var, 'juxedvarsonly');
    return node;
  } catch(e) {
    throw "Variable: " + this.var + " undeclared";
  }
};

nile.opdef.matchSig = function(name, fixity, argtype)
{
  return this.sig.name == name && this.sig.fixity == fixity &&
         this.sig.param.getType().isEqual(argtype);
};

nile.block.isEmpty = function()
{
  return this.vardefs.length == 0 && this.stmts.length == 0;
};
