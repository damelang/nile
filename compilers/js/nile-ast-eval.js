// TODO Instead of this, determine if types are compatible at compile time (i.e., type checking).
// Then, only the value duplication, and only if needed, will be done at runtime.
nile.coerce = function(value, type)
{
  var size = type.size();
  if (size == null) {
    if (value instanceof Array)
      throw "Cannot coerce aggregate to primitive";
    return value;
  }
  else {
    if (value instanceof Array) {
      if (value.length != size)
        throw "Cannot coerce aggregate to different size aggregate";
      return value;
    }
    else {
      var value_ = [];
      for (var i = 0; i < size; i++)
        value_.push(value);
      return value_;
    }
  }
};

nile.numexpr.eval      = function(env) { return this.value; };
nile.tupleexpr.eval    = function(env) { return this.elements.mapMethod('eval', env); };
nile.recfieldexpr.eval = function(env) { return this.record.eval(env)[this.field]; };
nile.varexpr.eval      = function(env) { return env.getVarValue(this.var.name); };

// TODO Clean this up by making the "otherwise" a part of the "cases"
// and unify the primitive/aggregate path
nile.condexpr.eval = function(env)
{
  // TODO calculate some of this at compile type
  var resultType = this.getType();
  var resultSize = resultType.size();
  var conditionType;
  var result;
  if (resultSize == null) {
    conditionType = nile.primtype();
    result = null;
  }
  else {
    conditionType = nile.tupletype(new Array(resultSize));
    result = new Array(resultSize);
  }

  for (var i = 0; i < this.cases.length; i++) {
    var c          = this.cases[i];
    var condition_ = nile.coerce(c.condition.eval(env), conditionType);
    var value_     = nile.coerce(c.value.eval(env), resultType);
    if (resultSize == null)
      result = result == null && condition_ ? value_ : result;
    else {
      for (var j = 0; j < resultSize; j++)
        result[j] = result[j] == null && condition_[j] ? value_[j] : result[j];
    }
  }

  var value_ = this.otherwise.eval(env);
  if (resultSize == null)
    result = result == null ? value_ : result;
  else {
    for (var j = 0; j < resultSize; j++)
      result[j] = result[j] == null ? value_[j] : result[j];
  }

  return result;
};

nile.opbody.eval = function(env)
{
  this.vardefs.forEach(function(v) { v.eval(env); });
  return this.result.eval(env);
};

nile.opexpr.eval = function(env)
{
  var arg_ = this.arg.eval(env);
  if (this.op.body.prototype.constructor !== nile.opbody)
    return this.op.body(arg_);
  var env_ = new nile.Environment();
  this.op.sig.param.evalWithValue(env_, arg_);
  return nile.coerce(this.op.body.eval(env_), this.op.sig.type);
};

// TODO work most of this out at compile time
nile.processbody.eval = function(env)
{
  var i = 0;
  var MAX_ITERS = 10000;
  while (env.hasInput()) {
    this.forpat.evalWithValue(env, env.consumeInput());
    this.block.eval(env);
    var vars = env.getVars();
    var vars_ = {};
    for (var v in vars) {
      if (v[v.length - 1] == "'")
        vars_[v] = vars[v];
    }
    for (var v_ in vars_) {
      var v = v_.slice(0, -1); // TODO at compile time, make sure a matching "v" exists in vars
      vars[v] = vars_[v_];
    }
    env.setVars(vars);
    if (i++ > MAX_ITERS) {
      debugger;
    }
  }
};

nile.processinst.eval = function(env)
{
  var processdef_ = env.getProcessdef(this.processdef);
  if (processdef_ == null)
    throw "Couldn't find process definition for " + this.processdef;
  var arg_ = this.arg.eval(env);
  return nile.processinst(processdef_, arg_);
};

nile.pipeline.eval = function(env)
{
  var producer_ = this.producer.eval(env);
  var consumer_ = this.consumer && this.consumer.eval(env);
  return nile.pipeline(producer_, consumer_);
};

nile.processinst.run = function(env)
{
  var pdef = this.processdef;
  console.log("Running process " + pdef.sig.name);
  env.setVars({});
  if (pdef.body.eval)
    env.traceOutput = [];
  env.traceRanges = [];
  env.traceRanges.push(pdef.sig.sourceCodeRange);
  pdef.sig.param.evalWithValue(env, this.arg);
  try {
    (pdef.prologue.eval || pdef.prologue).call(pdef.prologue, env);
    (pdef.body.eval     || pdef.body)    .call(pdef.body,     env);
    (pdef.epilogue.eval || pdef.epilogue).call(pdef.epilogue, env);
  }
  catch(e) {
    if (e !== nile.substmt)
      throw e;
  }
  console.log("Finished process " + pdef.sig.name);
};

nile.pipeline.run = function(env)
{
  this.producer.run(env);
  if (this.consumer) {
    env.swapInputAndOutput();
    this.consumer.run(env);
  }
};

nile.vardecl.evalWithValue = function(env, value)
{ 
  env.setVarValue(this.name, nile.coerce(value, this.type));
};

nile.tuplepat.evalWithValue = function(env, value)
{ 
  this.elements.forEach(function(e, i) { e.evalWithValue(env, value[i]); });
};

nile.vardef.eval = function(env)
{ 
    this.lvalue.evalWithValue(env, this.rvalue.eval(env));
};

nile.ifstmt.eval = function(env)
{
  var condition_ = this.condition.eval(env);   
  if (condition_)
      this.tblock.eval(env);
  else
      this.fblock.eval(env);
};

nile.instmt.eval = function(env)
{
  // TODO coerce
  for (var i = 0; i < this.values.length; i++)
    env.prefixInput(this.values[i].eval(env));
};

nile.outstmt.eval = function(env)
{
  // TODO coerce
  for (var i = this.values.length - 1; i >= 0; i--) {
    env.appendOutput(this.values[i].eval(env));
    env.appendTrace();
  }
};

nile.block.eval = function(env)
{
  this.vardefs.forEach(function(v) { v.eval(env); });
  this.stmts.forEach  (function(s) { s.eval(env); });
};

nile.substmt.eval = function(env)
{
  this.pipeline.eval(env).run(env);
  throw nile.substmt;
};
