{BSOMetaJSParser=objectThatDelegatesTo(BSJSParser,{
"srcElem":function(){var $elf=this,_fromIdx=this.input.idx,r;return this._or((function(){return (function(){this._apply("spaces");r=this._applyWithArgs("foreign",BSOMetaParser,'grammar');this._apply("sc");return r}).call(this)}),(function(){return BSJSParser._superApplyWithArgs(this,'srcElem')}))}});BSOMetaJSTranslator=objectThatDelegatesTo(BSJSTranslator,{
"Grammar":function(){var $elf=this,_fromIdx=this.input.idx;return this._applyWithArgs("foreign",BSOMetaTranslator,'Grammar')}})}
