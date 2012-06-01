nile.builtin = {};
nile.builtin.env = new nile.Environment();

nile.builtin.typedefs = [
  "type Boolean",
  "type Number"
];

nile.builtin.opdefs = [
  {sig: "¬a:Boolean : Boolean",            body: function(arg) { return !arg; }},
  {sig: "a:Boolean ∨ b:Boolean : Boolean", body: function(arg) { return arg[0] || arg[1]; }},
  {sig: "a:Boolean ∧ b:Boolean : Boolean", body: function(arg) { return arg[0] && arg[1]; }},
  {sig: "-a:Number : Number",              body: function(arg) { return -arg; }},
  {sig: "√a:Number : Number",              body: function(arg) { return Math.sqrt(arg); }},
  {sig: "⌊a:Number⌋ : Number",             body: function(arg) { return Math.floor(arg); }},
  {sig: "⌈a:Number⌉ : Number",             body: function(arg) { return Math.ceil(arg); }},
  {sig: "a:Number = b:Number : Boolean",   body: function(arg) { return arg[0] == arg[1]; }},
  {sig: "a:Number ≠ b:Number : Boolean",   body: function(arg) { return arg[0] != arg[1]; }},
  {sig: "a:Number < b:Number : Boolean",   body: function(arg) { return arg[0] < arg[1]; }},
  {sig: "a:Number ≤ b:Number : Boolean",   body: function(arg) { return arg[0] <= arg[1]; }},
  {sig: "a:Number > b:Number : Boolean",   body: function(arg) { return arg[0] > arg[1]; }},
  {sig: "a:Number ≥ b:Number : Boolean",   body: function(arg) { return arg[0] >= arg[1]; }},
  {sig: "a:Number + b:Number : Number",    body: function(arg) { return arg[0] + arg[1]; }},
  {sig: "a:Number - b:Number : Number",    body: function(arg) { return arg[0] - arg[1]; }},
  {sig: "a:Number   b:Number : Number",    body: function(arg) { return arg[0] * arg[1]; }},
  {sig: "a:Number / b:Number : Number",    body: function(arg) { return arg[0] / arg[1]; }}
];

nile.builtin.processdefs = [

  {sig: "PassThrough () : α >> α",
   prologue: function(env) { },
   body:     function(env) {
       env.output = env.output.concat(env.input);
       env.input = [];
   },
   epilogue: function(env) { }},

  {sig: "Reverse () : α >> α",
   prologue: function(env) { },
   body:     function(env) {
     env.input.reverse();
     env.swapInputAndOutput();
   },
   epilogue: function(env) { }},

  {sig: "SortBy (f:Number) : α >> α",
   prologue: function(env) { },
   body:     function(env) {
     var f = env.getVarValue("f") - 1;
     env.input = nile.stableSort(env.input, function(a) { return a[f]; });
     env.swapInputAndOutput();
   },
   epilogue: function(env) { }},

  {sig: "DupZip (p1:(α >> β), p2:(α >> γ)) : α >> (β, γ)",
   prologue: function(env) {
     var p1 = env.getVarValue("p1");
     var p2 = env.getVarValue("p2");
     var input = env.input.slice(0);
     p1.run(env);
     var output1 = env.output;
     env.input = input;
     env.output = [];
     p2.run(env);
     var output2 = env.output;
     env.output = output1.map(function(e, i) { return [e, output2[i]]; });
     throw nile.substmt;
   },
   body:     function(env) { },
   epilogue: function(env) { }},

  {sig: "DupCat (p1:(α >> β), p2:(α >> β)) : α >> β",
   prologue: function(env) {
     var p1 = env.getVarValue("p1");
     var p2 = env.getVarValue("p2");
     var input = env.input.slice(0);
     p1.run(env);
     var output1 = env.output;
     env.input = input;
     env.output = [];
     p2.run(env);
     var output2 = env.output;
     env.output = output1.concat(output2);
     throw nile.substmt;
   },
   body:     function(env) { },
   epilogue: function(env) { }},
];

nile.builtin.env.init = function(parser)
{
  var env = this;
  nile.builtin.typedefs.forEach(function(typedef) {
    parser.matchAll(typedef, "typedef").resolve(env);
  });

  nile.builtin.opdefs.forEach(function(opdef) {
    env.pushScope();
      var sig_ = parser.matchAll(opdef.sig, "opsig").resolve(env);
    env.popScope();
    env.addOpdef(nile.opdef(sig_, opdef.body));
  });

  nile.builtin.processdefs.forEach(function(pdef) {
    env.pushScope();
      var sig_ = parser.matchAll(pdef.sig, "processsig").resolve(env);
    env.popScope();
    var pdef_ = nile.processdef(sig_, pdef.prologue, pdef.body, pdef.epilogue);
    env.addProcessdef(pdef_);
  });
};
