function translateCode(s) {
  var translationError = function(m, i) { alert("Translation error - please tell Alex about this!"); throw fail },
      tree             = BSOMetaJSParser.matchAll(s, "topLevel", undefined, function(m, i) {
                                                                              throw objectThatDelegatesTo(fail, {errorPos: i}) })
  return BSOMetaJSTranslator.match(tree, "trans", undefined, translationError)
}
   
origOnload = window.onload
window.onload = function() {
  var scripts = document.getElementsByTagName("script")
  for (var idx = 0; idx < scripts.length; idx++) {
    var script = scripts[idx]
    if (script.type === "text/x-ometa-js")
      eval(translateCode(script.innerHTML))
  }
  if (typeof origOnload === "string")
    eval(origOnload)
  else if (typeof origOnload === "function")
    origOnload()
}

