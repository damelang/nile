var nile = {};

nile.debug = function(s) {
  document.body.appendChild(document.createElement('div')).innerHTML = s;
};

nile.Pipeline = function() {
  var ks = arguments;
  return function(downstream) {
    return function(input) {
      var k = downstream;
      for (var i = ks.length - 1; i >= 0; i--)
        k = ks[i](k);
      k(input);
    };
  };
};

nile.Reverse = function(quantum) {
  return function(downstream) {
    return function(input) {
      var output = [];
      var i = 0;
      var j = input.length;
      while (i < input.length) {
        for (var jj = j - quantum; jj < j; jj++)
          output[jj] = input[i++];
        j -= quantum;
      }
      downstream(output);
    };
  };
};

nile.GroupBy = function(index, quantum, k) {
  return function(downstream) {
    return function(input) {
      k = k(downstream); // FIXME this is silly
      var output;
      nile.SortBy(index, quantum)(function(input) { output = input; })(input)
      var group = [];
      var key = output[index];
      while (output.length) {
        var key_ = output[index];
        if (key != key_) {
          k(group);
          group = [];
          key = key_;
        }
        for (var i = 0; i < quantum; i++)
          group.push(output.shift());
      }
      k(group);
    };
  };
};

nile.SortBy = function(index, quantum) {
  return function(downstream) {
    return function(input) {
      var vectors = [];
      for (var i = 0; i < input.length; i += quantum)
        vectors.push(input.slice(i, i + quantum));
      vectors.sort(function(a, b) {
        if (a[index] < b[index])
          return -1;
        else if (a[index] > b[index])
          return 1;
        else
          return 0;
      });
      var output = [];
      for (var i = 0; i < vectors.length; i++)
        for (var j = 0; j < quantum; j++)
          output.push(vectors[i][j]);
      downstream(output);
    };
  };
};

nile.Interleave = function(k1, quantum1, k2, quantum2) {
  return function(downstream) {
    return function(input) {
      var out1;
      var out2;
      var output = [];
      k1(function(input) { out1 = input; })(input.slice(0));
      k2(function(input) { out2 = input; })(input);
      while (out1.length) {
        for (var j = 0; j < quantum1; j++)
          output.push(out1.shift());
        for (var j = 0; j < quantum2; j++)
          output.push(out2.shift());
      }
      downstream(output);
    };
  };
};

nile.Mix = function(k1, k2) {
  return function(downstream) {
    return function(input) {
      var output = [];
      k1(function(input) { output = input; })(input.slice(0));
      k2(function(input) { output = output.concat(input); })(input);
      downstream(output);
    };
  };
};
