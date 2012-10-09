nile.typeref.resolve = function(env)
{
  return env.getTypedef(this.name) || this;
};

nile.vardecl.resolve = function(env)
{
  var type_ = this.type.resolve(env);
  var this_ = nile.vardecl(this.name, type_);
  return env.addVardecl(this_);
};

nile.vardecl.resolveWithType = function(env, type)
{
  var type_ = this.type.prototype.constructor == nile.anytype ?
              type : this.type.resolve(env);
  var this_ = nile.vardecl(this.name, type_);
  return env.addVardecl(this_);
};

nile.tuplepat.resolveWithType = function(env, type)
{
  var types = type.innerTypes();
  var elements_ = this.elements.map(function(e, i) {
    return e.resolveWithType(env, types[i]);
  });
  return nile.tuplepat(elements_);
};

nile.numexpr.resolve = function(env)
{
  var value_ = this.value == "∞" ? Infinity : parseFloat(this.value);
  return nile.numexpr(value_);
};

nile.recfieldexpr.resolve = function(env)
{
  var record_ = this.record.resolve(env);
  var field_  = record_.getType().getFieldIndex(this.field);
  return nile.recfieldexpr(record_, field_);
};

nile.opexpr.resolve = function(env)
{
  this.arg = (this.arg instanceof Array) ? nile.tupleexpr(this.arg) : this.arg;
  if (this.isChainedRelational())
    return this.unchainRelational().resolve(env);
  var arg_ = this.arg.resolve(env);
  var op_  = env.getOpdef(this.op, this.fixity, arg_.getType());
  return nile.opexpr(op_, this.fixity, arg_);
};

nile.varexpr.resolve = function(env)
{
  var var_ = env.getVardecl(this.var);
  if (!var_) {
    try      { var this_ = this.splitVars(); }
    catch(e) { throw "Variable: " + this.var + " undeclared"; }
    return this_.resolve(env);
  }
  return nile.varexpr(var_);
};

nile.vardef.resolve = function(env)
{
  var rvalue_ = this.rvalue.resolve(env);
  var lvalue_ = this.lvalue.resolveWithType(env, rvalue_.getType());
  return nile.vardef(lvalue_, rvalue_);
};

nile.typedef.resolve = function(env)
{
  env.pushScope();
    var type_ = this.type.resolve(env);
  env.popScope();
  var this_ = nile.typedef(this.name, type_);
  return env.addTypedef(this_);
};

nile.opsig.resolve = function(env)
{
  var param_ = this.param.resolve(env);
  var type_  = this.type.resolve(env);
  return nile.opsig(this.name, this.fixity, param_, type_);
};

nile.opdef.resolve = function(env)
{
  env.pushScope();
    var sig_ = this.sig.resolve(env);
    var paramType = sig_.param.getType();
    var this_ = this.body ? nile.opdef(sig_, this.body.resolve(env)) :
                            nile.builtin.env.getOpdef(sig_.name, sig_.fixity, paramType);
    // what if builtin opdef has different return value?
  env.popScope();
  return env.addOpdef(this_);
};

nile.ifstmt.resolve = function(env)
{
  var condition_ = this.condition.resolve(env);
  env.pushScope();
    var tblock_ = this.tblock.resolve(env);
  env.popScope();
  env.pushScope();
    var fblock_ = this.fblock.resolve(env);
  env.popScope();
  return nile.ifstmt(condition_, tblock_, fblock_);
};

nile.processinst.resolve = function(env)
{
  // Resolve processdef at interpretation time (for incremental compiling).
  var arg_ = this.arg.resolve(env);
  return nile.processinst(this.processdef, arg_);
};

nile.processsig.resolve = function(env)
{
  var param_ = this.param.resolve(env);
  var type_  = this.type.resolve(env);
  var this_  = nile.processsig(this.name, param_, type_);
  env.addProcessdef(nile.processdef(this_, null, null, null));
  return this_;
};

nile.processbody.resolveWithType = function(env, type)
{
  var forpat_ = this.forpat.resolveWithType(env, type);
  var block_  = this.block.resolve(env);
  return nile.processbody(forpat_, block_);
};

nile.processdef.resolve = function(env)
{
  env.pushScope();
    var sig_ = this.sig.resolve(env);
    var this_;
    if (this.prologue.isEmpty() && !this.body) {
      this_ = nile.builtin.env.getProcessdef(sig_.name);
      // check that the process sigs match?
    }
    else {
      var prologue_ = this.prologue.resolve(env);
      var intype = sig_.getType().getIntype();
      env.pushScope();
        var body_ = this.body ? this.body.resolveWithType(env, intype) :
                                nile.builtin.env.getProcessdef("PassThrough").body;
      env.popScope();
      var epilogue_ = this.epilogue.resolve(env);
      this_ = nile.processdef(sig_, prologue_, body_, epilogue_);
    }
  env.popScope();
  env.addProcessdef(this_);
  return this_;
};
