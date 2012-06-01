nile.Environment = function()
{
  this.typedefs = [];
  this.opdefs = [];
  this.processdefs = [];
  this.scopes = [];

  this.vars = {};
  this.output = [];
  this.input = [];

  return this;
};

nile.Environment.prototype.addTypedef = function(typedef)
{
  this.typedefs.push(typedef);
  return typedef;
};

nile.Environment.prototype.getTypedef = function(name)
{
  return this.typedefs.detect(function(t) { return t.name == name; });
};

nile.Environment.prototype.getTypedefs = function()
{
  return this.typedefs;
};

nile.Environment.prototype.pushScope = function()
{
  this.scopes.push({});
};

nile.Environment.prototype.popScope = function()
{
  this.scopes.pop();
};

nile.Environment.prototype.addVardecl = function(vardecl)
{
  if (vardecl.name == "_")
    return vardecl;
  var scope = this.scopes[this.scopes.length - 1];
  scope[vardecl.name] = vardecl;
  return vardecl;
};

nile.Environment.prototype.getVardecl = function(name)
{
  var scope = this.scopes.detect(function(s) { return s[name]; });
  return scope && scope[name];
};

nile.Environment.prototype.addOpdef = function(opdef)
{
  this.opdefs.push(opdef);
  return opdef;
};

nile.Environment.prototype.getOpdef = function(name, fixity, paramType)
{
  return this.opdefs.detect(function(opdef) {
    return opdef.matchSig(name, fixity, paramType);
  });
};

nile.Environment.prototype.getOpdefs = function()
{
  return this.opdefs;
};

nile.Environment.prototype.addProcessdef = function(processdef)
{
  var i = this.processdefs.detectIndex(function(p) { return p.sig.name == processdef.sig.name; });
  if (i >= 0)
    this.processdefs.splice(i, 1);
  this.processdefs.push(processdef);
  return processdef;
};

nile.Environment.prototype.getProcessdef = function(name)
{
  return this.processdefs.detect(function(p) {
    return p.sig.name == name;
  });
};

nile.Environment.prototype.getProcessdefs = function()
{
  return this.processdefs;
};

// TODO variable shadowing is not supported right now!

nile.Environment.prototype.setVarValue = function(name, value) { if (name != "_") this.vars[name] = value; };

nile.Environment.prototype.getVarValue = function(name) { return this.vars[name]; }

nile.Environment.prototype.getVars = function() { return this.vars; };

nile.Environment.prototype.setVars = function(vars) { this.vars = vars; };

nile.Environment.prototype.setInput = function(input) { this.input = input; };

nile.Environment.prototype.hasInput = function() { return this.input.length != 0; };

nile.Environment.prototype.consumeInput = function() { return this.input.shift(); };

nile.Environment.prototype.prefixInput = function(value) { this.input.unshift(value); };

nile.Environment.prototype.appendOutput = function(value) { this.output.push(value); };

nile.Environment.prototype.getOutput = function() { return this.output; };

nile.Environment.prototype.swapInputAndOutput = function()
{
  var input = this.input;
  this.input = this.output;
  this.output = input;
};

nile.Environment.prototype.clear = function() { this.input = []; this.output = []; this.vars = {}; };
