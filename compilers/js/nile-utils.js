var nile = {};

nile.stableSort = function(array, extractKey)
{
  var keysIndicesValues = array.map(function(value, index) {
      return [extractKey(value), index, value];
  });
  keysIndicesValues.sort(function(a, b) {
    var result = a[0] - b[0];
    return result == 0 ? a[1] - b[1] : result;
  });
  return keysIndicesValues.map(function(kiv) { return kiv[2]; });
};

function cons(a, b) { return [a].concat(b); }

Array.prototype.detectIndex = function(predicate)
{
  for (var i = 0; i < this.length; i++)
    if (predicate(this[i]))
      return i;
  return -1;
};

Array.prototype.detect = function(predicate)
{
  var i = this.detectIndex(predicate);
  if (i >= 0)
      return this[i];
};

Array.prototype.mapMethod = function()
{
  var method = arguments[0];
  var args = Array.prototype.slice.call(arguments, 1);
  return this.map(function(e) {
    return e[method].apply(e, args);
  });
};

if (!Array.prototype.map) {  
  Array.prototype.map = function(callback, thisArg) {  
  
    var T, A, k;  
  
    if (this == null) {  
      throw new TypeError(" this is null or not defined");  
    }  
  
    // 1. Let O be the result of calling ToObject passing the |this| value as the argument.  
    var O = Object(this);  
  
    // 2. Let lenValue be the result of calling the Get internal method of O with the argument "length".  
    // 3. Let len be ToUint32(lenValue).  
    var len = O.length >>> 0;  
  
    // 4. If IsCallable(callback) is false, throw a TypeError exception.  
    // See: http://es5.github.com/#x9.11  
    if ({}.toString.call(callback) != "[object Function]") {  
      throw new TypeError(callback + " is not a function");  
    }  
  
    // 5. If thisArg was supplied, let T be thisArg; else let T be undefined.  
    if (thisArg) {  
      T = thisArg;  
    }  
  
    // 6. Let A be a new array created as if by the expression new Array(len) where Array is  
    // the standard built-in constructor with that name and len is the value of len.  
    A = new Array(len);  
  
    // 7. Let k be 0  
    k = 0;  
  
    // 8. Repeat, while k < len  
    while(k < len) {  
  
      var kValue, mappedValue;  
  
      // a. Let Pk be ToString(k).  
      //   This is implicit for LHS operands of the in operator  
      // b. Let kPresent be the result of calling the HasProperty internal method of O with argument Pk.  
      //   This step can be combined with c  
      // c. If kPresent is true, then  
      if (k in O) {  
  
        // i. Let kValue be the result of calling the Get internal method of O with argument Pk.  
        kValue = O[ k ];  
  
        // ii. Let mappedValue be the result of calling the Call internal method of callback  
        // with T as the this value and argument list containing kValue, k, and O.  
        mappedValue = callback.call(T, kValue, k, O);  
  
        // iii. Call the DefineOwnProperty internal method of A with arguments  
        // Pk, Property Descriptor {Value: mappedValue, Writable: true, Enumerable: true, Configurable: true},  
        // and false.  
  
        // In browsers that support Object.defineProperty, use the following:  
        // Object.defineProperty(A, Pk, { value: mappedValue, writable: true, enumerable: true, configurable: true });  
  
        // For best browser support, use the following:  
        A[ k ] = mappedValue;  
      }  
      // d. Increase k by 1.  
      k++;  
    }  
  
    // 9. return A  
    return A;  
  };        
}  

if (!Array.prototype.filter)  
{  
  Array.prototype.filter = function(fun /*, thisp */)  
  {  
    "use strict";  
  
    if (this == null)  
      throw new TypeError();  
  
    var t = Object(this);  
    var len = t.length >>> 0;  
    if (typeof fun != "function")  
      throw new TypeError();  
  
    var res = [];  
    var thisp = arguments[1];  
    for (var i = 0; i < len; i++)  
    {  
      if (i in t)  
      {  
        var val = t[i]; // in case fun mutates this  
        if (fun.call(thisp, val, i, t))  
          res.push(val);  
      }  
    }  
  
    return res;  
  };  
}  

if (!Array.prototype.reduceRight)  
{  
  Array.prototype.reduceRight = function(callbackfn /*, initialValue */)  
  {  
    "use strict";  
  
    if (this == null)  
      throw new TypeError();  
  
    var t = Object(this);  
    var len = t.length >>> 0;  
    if (typeof callbackfn != "function")  
      throw new TypeError();  
  
    // no value to return if no initial value, empty array  
    if (len === 0 && arguments.length === 1)  
      throw new TypeError();  
  
    var k = len - 1;  
    var accumulator;  
    if (arguments.length >= 2)  
    {  
      accumulator = arguments[1];  
    }  
    else  
    {  
      do  
      {  
        if (k in this)  
        {  
          accumulator = this[k--];  
          break;  
        }  
  
        // if array contains no values, no initial value to return  
        if (--k < 0)  
          throw new TypeError();  
      }  
      while (true);  
    }  
  
    while (k >= 0)  
    {  
      if (k in t)  
        accumulator = callbackfn.call(undefined, accumulator, t[k], k, t);  
      k--;  
    }  
  
    return accumulator;  
  };  
}  

if (!Array.prototype.every)  
{  
  Array.prototype.every = function(fun /*, thisp */)  
  {  
    "use strict";  
  
    if (this == null)  
      throw new TypeError();  
  
    var t = Object(this);  
    var len = t.length >>> 0;  
    if (typeof fun != "function")  
      throw new TypeError();  
  
    var thisp = arguments[1];  
    for (var i = 0; i < len; i++)  
    {  
      if (i in t && !fun.call(thisp, t[i], i, t))  
        return false;  
    }  
  
    return true;  
  };  
}   

if ( !Array.prototype.forEach ) {  
  
  Array.prototype.forEach = function( callback, thisArg ) {  
  
    var T, k;  
  
    if ( this == null ) {  
      throw new TypeError( "this is null or not defined" );  
    }  
  
    // 1. Let O be the result of calling ToObject passing the |this| value as the argument.  
    var O = Object(this);  
  
    // 2. Let lenValue be the result of calling the Get internal method of O with the argument "length".  
    // 3. Let len be ToUint32(lenValue).  
    var len = O.length >>> 0; // Hack to convert O.length to a UInt32  
  
    // 4. If IsCallable(callback) is false, throw a TypeError exception.  
    // See: http://es5.github.com/#x9.11  
    if ( {}.toString.call(callback) != "[object Function]" ) {  
      throw new TypeError( callback + " is not a function" );  
    }  
  
    // 5. If thisArg was supplied, let T be thisArg; else let T be undefined.  
    if ( thisArg ) {  
      T = thisArg;  
    }  
  
    // 6. Let k be 0  
    k = 0;  
  
    // 7. Repeat, while k < len  
    while( k < len ) {  
  
      var kValue;  
  
      // a. Let Pk be ToString(k).  
      //   This is implicit for LHS operands of the in operator  
      // b. Let kPresent be the result of calling the HasProperty internal method of O with argument Pk.  
      //   This step can be combined with c  
      // c. If kPresent is true, then  
      if ( k in O ) {  
  
        // i. Let kValue be the result of calling the Get internal method of O with argument Pk.  
        kValue = O[ k ];  
  
        // ii. Call the Call internal method of callback with T as the this value and  
        // argument list containing kValue, k, and O.  
        callback.call( T, kValue, k, O );  
      }  
      // d. Increase k by 1.  
      k++;  
    }  
    // 8. return undefined  
  };  
}  
