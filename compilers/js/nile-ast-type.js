// Methods on types

nile.primtype.size    = function() { return null; };
nile.recordtype.size  = function() { return this.fields.length; };
nile.tupletype.size   = function() { return this.types.length; };
nile.processtype.size = function() { return null; };
nile.typedef.size     = function() { return this.type.size(); };

nile.recordtype.innerTypes = function() { return this.fields.mapMethod('getType'); };
nile.tupletype.innerTypes  = function() { return this.types; };
nile.typedef.innerTypes    = function() { return this.type.innerTypes(); };

nile.recordtype.getField = function(index) { return this.fields[index]; };
nile.typedef.getField    = function(index) { return this.type.getField(index); };

nile.recordtype.getFieldIndex = function(fieldname)
{
  return this.fields.detectIndex(function(f) { return f.name == fieldname; });
};
nile.typedef.getFieldIndex = function(fieldname) { return this.type.getFieldIndex(fieldname); };

nile.processtype.getIntype  = function() { return this.intype; };
nile.typedef.getIntype      = function() { return this.type.getIntype(); };
nile.processtype.getOuttype = function() { return this.outtype; };
nile.typedef.getOuttype     = function() { return this.type.getOuttype(); };

// Type equality

nile.typedef.isEqual = function(type)
{
  return this.prototype.constructor == type.prototype.constructor &&
         this.name == type.name;
};

nile.tupletype.isEqual = function(type)
{
  if (this.prototype.constructor != type.prototype.constructor)
    return false;
  var types1 = this.innerTypes();
  var types2 = type.innerTypes();
  return types1.length == types2.length &&
         types1.every(function(t1, i) { return t1.isEqual(types2[i]); });
};

nile.recordtype.isEqual  = function(type) { return false; }
nile.processtype.isEqual = function(type) { return false; }

// Getting the type of a node

nile.vardecl.     getType = function() { return this.type; };
nile.tuplepat.    getType = function() { return nile.tupletype(this.elements.mapMethod('getType')); };
nile.numexpr.     getType = function() { return nile.typedef("Number", nile.primtype()); };
nile.varexpr.     getType = function() { return this.var.getType(); };
nile.tupleexpr.   getType = function() { return nile.tupletype(this.elements.mapMethod('getType')); };
nile.condcase.    getType = function() { return this.value.getType(); };
nile.condexpr.    getType = function() { return this.cases[0].getType(); };
nile.recfieldexpr.getType = function() { return this.record.getType().getField(this.field).getType(); };
nile.opexpr.      getType = function() { return this.op.getType(); };
nile.processinst. getType = function() { return this.processdef.getType(); };
nile.opsig.       getType = function() { return this.type; };
nile.opbody.      getType = function() { return this.result.getType(); };
nile.opdef.       getType = function() { return this.sig.getType(); };
nile.processsig.  getType = function() { return this.type; };
nile.processdef.  getType = function() { return this.sig.getType(); };
