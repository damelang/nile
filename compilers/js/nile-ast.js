var nile = {};

(function () {
  var String_toString_old = String.prototype.toString;
  String.prototype.toString = function() {
    if (arguments[0])
      return String_toString_old.call(this) + "\n";
    else
      return String_toString_old.call(this);
  }
  var Array_toString_old = Array.prototype.toString;
  Array.prototype.toString = function() {
    var col  = arguments[0];
    var col_ = col ? col + 4 : 0;
    var indentation = Array(col_).join(" ");
    var s = "[\n";
    if (col) {
      for (var i = 0; i < this.length; i++) {
        s += indentation;
        s += (this[i] == null ? "<null>\n" : this[i].toString(col_));
      }
      return s + Array(col).join(" ") + "]\n";
    }
    else
      return Array_toString_old.call(this);
  }
}) ();

nile.defineASTNode = function(name, fieldnames) {
  var node = function(fieldvalues) {
    for (var i = 0; i < fieldnames.length; i++)
      this[fieldnames[i]] = fieldvalues[i];
    return this;
  };
  node.prototype.toString = function() {
    var col  = arguments[0] || 0;
    var col_ = col + 4;
    var indentation = Array(col_).join(" ");
    var s = name + " {\n";
    for (var i = 0; i < fieldnames.length; i++) {
      var fieldvalue = this[fieldnames[i]];
      s += indentation + fieldnames[i] + "=";
      s += (fieldvalue == null ? "<null>\n" : fieldvalue.toString(col_));
    }
    return s + Array(col).join(" ") + "}\n";
  };
  nile[name] = function() { return new node(arguments); };
}

nile.defineASTNode("vardecl",      ["name", "type"]);
nile.defineASTNode("tupletype",    ["types"]);
nile.defineASTNode("recordtype",   ["fields"]);
nile.defineASTNode("processtype",  ["intype", "outtype"]);
nile.defineASTNode("realexpr",     ["value"]);
nile.defineASTNode("intexpr",      ["value"]);
nile.defineASTNode("varexpr",      ["var"]);
nile.defineASTNode("tupleexpr",    ["elements"]);
nile.defineASTNode("condcase",     ["value", "condition"]);
nile.defineASTNode("condexpr",     ["cases", "default"]);
nile.defineASTNode("recfieldexpr", ["record", "field"]);
nile.defineASTNode("opexpr",       ["op", "args"]);
nile.defineASTNode("processinst",  ["process", "args"]);
nile.defineASTNode("pipeline",     ["process", "downstream"]);
nile.defineASTNode("varpat",       ["decls"]);
nile.defineASTNode("vardef",       ["pat", "value"]);
nile.defineASTNode("instmt",       ["values"]);
nile.defineASTNode("outstmt",      ["values"]);
nile.defineASTNode("ifstmt",       ["condition", "true", "false"]);
nile.defineASTNode("substmt",      ["pipeline"]);
nile.defineASTNode("block",        ["vardefs", "stmts"]);
nile.defineASTNode("typedef",      ["name", "type"]);
nile.defineASTNode("opsig",        ["name", "params", "type"]);
nile.defineASTNode("opbody",       ["vardefs", "value"]);
nile.defineASTNode("opdef",        ["sig", "body"]);
nile.defineASTNode("processsig",   ["name", "params", "type"]);
nile.defineASTNode("processbody",  ["varpat", "block"]);
nile.defineASTNode("processdef",   ["sig", "prologue", "body", "epilogue"]);
