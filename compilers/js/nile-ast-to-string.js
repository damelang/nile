nile.primtype.toString   = function() { return "primtype\n"; }
nile.anytype.toString    = function() { return "anytype\n"; }
nile.vardecl.toString    = function() { return this.name + ":" + this.type.toString(arguments[0]); };
nile.tupletype.toString  = function() { return this.types.toString(arguments[0]); };
nile.recordtype.toString = function() { return this.fields.toString(arguments[0]); };
nile.typeref.toString    = function() { return "\"" + this.name + "\""; };
nile.numexpr.toString    = function() { return this.value + "\n"; };
nile.varexpr.toString    = function() { return this.var.toString(arguments[0]); };
nile.tuplepat.toString   = function() { return this.elements.toString(arguments[0]); };

nile.typedef.toString_old = nile.typedef.toString;
nile.typedef.toString = function()
{
  var n = arguments[0] || 0;
  return n == 0 ? nile.typedef.toString_old.call(this, n) :
                  this.name;
};

nile.opsig.toString_old = nile.opsig.toString;
nile.opsig.toString = function()
{
  var n = arguments[0] || 0;
  return n < 5 ? nile.opsig.toString_old.call(this, n) :
                 this.name + " " + this.param.toString(n);
};

nile.opdef.toString_old = nile.opdef.toString;
nile.opdef.toString = function()
{
  var n = arguments[0] || 0;
  return n == 0 ? nile.opdef.toString_old.call(this, n) :
                  this.sig.toString(n);
};

nile.processsig.toString_old = nile.processsig.toString;
nile.processsig.toString = function()
{
  var n = arguments[0] || 0;
  return n < 5 ? nile.processsig.toString_old.call(this, n) :
                 this.name + "\n";
};

nile.processdef.toString_old = nile.processdef.toString;
nile.processdef.toString = function()
{
  var n = arguments[0] || 0;
  return n == 0 ? nile.processdef.toString_old.call(this, n) :
                  this.sig.toString(n);
};
