;;; ./eval repl.l gen-asm-86.k

(println "(load \"asm-common.k\")")

{
  comment       = "//" (!newline .)*
                | "/*" (!"*/" .)* "*/" ;
  blank         = " " | "\t" | "\\"newline ;
  newline       = ("\r""\n"*) | ("\n""\r"*) ;
  _             = blank* ;
  __            = (blank | comment | newline)* ;
  identifier    = ([a-zA-Z_][a-zA-Z_0-9]*)@$$ ;
  name          = identifier:id _ -> id ;
  unumber       = ( "0x"[0-9A-Fa-f]+ @$#16 | [0-9]+ @$#10 ) :s _ -> s ;
  number        = "-" unumber:n -> `(- ,n)
                |     unumber ;
  string        = "\"" (!"\"".)*@$:s "\""_ ( "#"name )* -> s ;
  primary       = number | name | string | "("_ expressions:e ")"_ -> e ;
  arglist       = expression?:e _ (","_ expression)*:f -> `(,@e ,@f) ;
  suffix        = primary:a     ( "("                           _ arglist:b     ")"_            -> (cons a b):a )*              -> a ;
  prefix        = suffix ;
  mulop         = prefix:a      ( ("*"|"/"|"%")@$$:o            _ mulop:b                       -> (list o    a b):a    )*      -> a ;
  addop         = mulop:a       ( ("+"|"-")@$$:o                _ addop:b                       -> (list o    a b):a    )*      -> a ;
  shift         = addop:a       ( ("<<"|">>")@$$:o              _ shift:b                       -> (list o    a b):a    )*      -> a ;
  inequality    = shift:a       ( ("<="|"<"|">="|">")@$$:o      _ inequality:b                  -> (list o    a b):a    )*      -> a ;
  equality      = inequality:a  ( ("=="|"!=")@$$:o              _ equality:b                    -> (list o    a b):a    )*      -> a ;
  bitand        = equality:a    ( "&"!"&"                       _ bitand:b                      -> (list '&   a b):a    )*      -> a ;
  bitxor        = bitand:a      ( "^"                           _ bitxor:b                      -> (list '^   a b):a    )*      -> a ;
  bitor         = bitxor:a      ( "|"!"|"                       _ bitor:b                       -> (list '|   a b):a    )*      -> a ;
  logand        = bitor:a       ( "&&"                          _ logand:b                      -> (list 'and a b):a    )*      -> a ;
  logor         = logand:a      ( "||"                          _ logor:b                       -> (list 'or  a b):a    )*      -> a ;
  ternary       = logor:a       ( "?"                           _ ternary:b     ":"_ ternary:c  -> (list 'if a b c):a   )*      -> a ;
  expression    = ternary:a     ( "="!"="                       _ ternary:b                     -> (list 'set a b):a    )*      -> a ;
  expressions   = expression:a  ( (","_ expression )+:b -> `(let () ,a ,@b):a )? -> a ;
  paramlist     = name?:i (","_ name)*:j -> `(,@i ,@j) ;
  macrodef      = identifier:id "("_ paramlist:p ")"_  expressions:e -> (list 'define-function id p e) ;
  constdef      = identifier:id _ expressions:e -> (list 'define-constant id e) ;
  definition    = __ "#"_ "define"_ ( macrodef | constdef ):d -> (dumpln d) ;
  definition*
}

#define _b00            0
#define _b01            1
#define _b10            2
#define _b11            3
        
#define _b000           0
#define _b001           1
#define _b010           2
#define _b011           3
#define _b100           4
#define _b101           5
#define _b110           6
#define _b111           7

/*** REGISTERS ***/     /* [size,,number] */

#define _AL             0x10
#define _CL             0x11
#define _DL             0x12
#define _BL             0x13
#define _AH             0x14
#define _CH             0x15
#define _DH             0x16
#define _BH             0x17

#define _AX             0x20
#define _CX             0x21
#define _DX             0x22
#define _BX             0x23
#define _SP             0x24
#define _BP             0x25
#define _SI             0x26
#define _DI             0x27

#define _EAX            0x40
#define _ECX            0x41
#define _EDX            0x42
#define _EBX            0x43
#define _ESP            0x44
#define _EBP            0x45
#define _ESI            0x46
#define _EDI            0x47

#define _rS(R)          ((R)>>4)
#define _rN(R)          ((R)&0x7)

#define _r0P(R)         ((R)==0)
#define _rLP(R)         (((R)>=_AL)&&((R)<=_BL))
#define _rHP(R)         (((R)>=_AH)&&((R)<=_BH))
#define _r1P(R)         (_rS(R)==1)
#define _r2P(R)         (_rS(R)==2)
#define _r4P(R)         (_rS(R)==4)

#define _rL(R)          (_rLP(R) ? _rN(R) : ASMFAIL( "8-bit L register required"))
#define _rH(R)          (_rHP(R) ? _rN(R) : ASMFAIL( "8-bit H register required"))
#define _r1(R)          (_r1P(R) ? _rN(R) : ASMFAIL( "8-bit register required"))
#define _r2(R)          (_r2P(R) ? _rN(R) : ASMFAIL("16-bit register required"))
#define _r4(R)          (_r4P(R) ? _rN(R) : ASMFAIL("32-bit register required"))

#define _rAL(R)         (((R)==_AL)  ? _rN(R) : ASMFAIL( "AL register required"))
#define _rAX(R)         (((R)==_AX)  ? _rN(R) : ASMFAIL( "AX register required"))
#define _rEAX(R)        (((R)==_EAX) ? _rN(R) : ASMFAIL("EAX register required"))

/*** IMMEDIATES ***/

#define _u1P(I)         (((I) & 0xffffff00) == 0)
#define _u2P(I)         (((I) & 0xffff0000) == 0)

#define _s1(I)          (_s1P(I) ? (I) : ASMFAIL( "8-bit signed immediate required"))
#define _s2(I)          (_s2P(I) ? (I) : ASMFAIL("16-bit signed immediate required"))

#define _u1(I)          (_u1P(I) ? (I) : ASMFAIL( "8-bit unsigned immediate required"))
#define _u2(I)          (_u2P(I) ? (I) : ASMFAIL("16-bit unsigned immediate required"))

#define _d1(I)          (_s1P(I) ? (I) : ASMFAIL( "8-bit displacement out of range"))

/*** ASSEMBLER ***/

#define _M(M)           (((M)>3) ? ASMFAIL("internal error: mod = " #M) : (M))
#define _r(R)           (((R)>7) ? ASMFAIL("internal error: reg = " #R) : (R))
#define _m(M)           (((M)>7) ? ASMFAIL("internal error: r/m = " #M) : (M))
#define _s(S)           (((S)>3) ? ASMFAIL("internal error: memory scale = " #S) : (S))
#define _i(I)           (((I)>7) ? ASMFAIL("internal error: memory index = " #I) : (I))
#define _b(B)           (((B)>7) ? ASMFAIL("internal error: memory base = "  #B) : (B))

#define _Mrm(X,Md,R,M)  _B(X,(_M(Md)<<6)|(_r(R)<<3)|_m(M))
#define _SIB(X,Sc,I, B) _B(X,(_s(Sc)<<6)|(_i(I)<<3)|_b(B))

#define _SCL(S)         ((((S)==1) ? _b00 : \
                         (((S)==2) ? _b01 : \
                         (((S)==4) ? _b10 : \
                         (((S)==8) ? _b11 : ASMFAIL("illegal scale: " #S))))))

/* memory subformats */

#define _r_D(   X,R, D      )           (_Mrm(X,_b00,_rN(R),_b101 )                              ,_L(X,D))
#define _r_0B(  X,R,   B    )           (_Mrm(X,_b00,_rN(R),_r4(B))                                      )
#define _r_0BIS(X,R,   B,I,S)           (_Mrm(X,_b00,_rN(R),_b100 ),_SIB(X,_SCL(S),_r4(I),_r4(B))        )
#define _r_0DIS(X,R, D,  I,S)           (_Mrm(X,_b00,_rN(R),_b100 ),_SIB(X,_SCL(S),_r4(I),    5 ),_L(X,D))
#define _r_1B(  X,R, D,B    )           (_Mrm(X,_b01,_rN(R),_r4(B))                              ,_B(X,D))
#define _r_1BIS(X,R, D,B,I,S)           (_Mrm(X,_b01,_rN(R),_b100 ),_SIB(X,_SCL(S),_r4(I),_r4(B)),_B(X,D))
#define _r_4B(  X,R, D,B    )           (_Mrm(X,_b10,_rN(R),_r4(B))                              ,_L(X,D))
#define _r_4BIS(X,R, D,B,I,S)           (_Mrm(X,_b10,_rN(R),_b100 ),_SIB(X,_SCL(S),_r4(I),_r4(B)),_L(X,D))
 
#define _r_DB(  X,R, D,B    )           ((_s0P(D) ? _r_0B  (X,R,  B    ) : (_s1P(D) ? _r_1B(  X,R,D,B    ) : _r_4B(  X,R,D,B    ))))
#define _r_DBIS(X,R, D,B,I,S)           ((_s0P(D) ? _r_0BIS(X,R,  B,I,S) : (_s1P(D) ? _r_1BIS(X,R,D,B,I,S) : _r_4BIS(X,R,D,B,I,S))))
 
#define _r_X( X,R, D,B,I,S)             (_r0P(I)  ? (_r0P(B)   ? _r_D   (X,R,D            )   : \
                                                    (_ESP==(B) ? _r_DBIS(X,R,D,_ESP,_ESP,1)   : \
                                                                 _r_DB  (X,R,D,   B       ))) : \
                                         ((_r0P(B) ?             _r_0DIS(X,R,D,        I,S)   : \
                                          (((I)!=_ESP)         ? _r_DBIS(X,R,D,   B,   I,S)   : \
                                                                 ASMFAIL("illegal index register: %esp")))))

/* instruction formats */

/*       _format                                                     Opcd         ModR/M dN(rB,rI,Sc)     imm... */
        
#define  _d16(       X                            )  (                _B(X,0x66      )                               )
#define   _O(        X,OP                         )  (                _B(X,(OP)      )                               )
#define   _Or(       X,OP,R                       )  (                _B(X,(OP)|_r(R))                               )
#define  _OO(        X,OP                         )  ( _B(X,(OP)>>8), _B(X,(OP)      )                               )
#define  _OOr(       X,OP,R                       )  ( _B(X,(OP)>>8), _B(X,(OP)|_r(R))                               )
#define   _Os(       X,OP,B                       )  (     _s1P(B) ?  _B(X,(OP)|_b10 ) : _B(X,OP)                    )
#define     _sW(     X,                        W  )  (                                      _s1P(W) ? _B(X,W):_W(X,W))
#define     _sL(     X,                        L  )  (                                      _s1P(L) ? _B(X,L):_L(X,L))
#define   _O_W(      X,OP                     ,W  )  (         _O        (X,OP  )                            ,_W(X,W))
#define   _O_D1(     X,OP                     ,D  )  (         _O        (X,OP  )                           ,_D1(X,D))
#define   _O_D4(     X,OP                     ,D  )  (         _O        (X,OP  )                           ,_D4(X,D))
#define  _OO_D4(     X,OP                     ,D  )  (        _OO        (X,OP  )                           ,_D4(X,D))
#define   _Os_sW(    X,OP                     ,W  )  (         _Os       (X,OP,W)                           ,_sW(X,W))
#define   _Os_sL(    X,OP                     ,L  )  (         _Os       (X,OP,L)                           ,_sL(X,L))
#define   _O_W_B(    X,OP                     ,W,B)  (         _O        (X,OP  )                    ,_W(X,W),_B(X,B))
#define   _Or_B(     X,OP,R                   ,B  )  (         _Or       (X,OP,R)                            ,_B(X,B))
#define   _Or_W(     X,OP,R                   ,W  )  (         _Or       (X,OP,R)                            ,_W(X,W))
#define   _Or_L(     X,OP,R                   ,L  )  (         _Or       (X,OP,R)                            ,_L(X,L))
#define   _O_Mrm(    X,OP  ,MO,R,M                )  (         _O        (X,OP  ),_Mrm(X,MO,R,M            )         )
#define  _OO_Mrm(    X,OP  ,MO,R,M                )  (        _OO        (X,OP  ),_Mrm(X,MO,R,M            )         )
#define   _O_Mrm_B(  X,OP  ,MO,R,M            ,B  )  (         _O        (X,OP  ),_Mrm(X,MO,R,M            ) ,_B(X,B))
#define   _O_Mrm_W(  X,OP  ,MO,R,M            ,W  )  (         _O        (X,OP  ),_Mrm(X,MO,R,M            ) ,_W(X,W))
#define   _O_Mrm_L(  X,OP  ,MO,R,M            ,L  )  (         _O        (X,OP  ),_Mrm(X,MO,R,M            ) ,_L(X,L))
#define  _OO_Mrm_B(  X,OP  ,MO,R,M            ,B  )  (        _OO        (X,OP  ),_Mrm(X,MO,R,M            ) ,_B(X,B))
#define   _Os_Mrm_sW(X,OP  ,MO,R,M            ,W  )  (         _Os       (X,OP,W),_Mrm(X,MO,R,M            ),_sW(X,W))
#define   _Os_Mrm_sL(X,OP  ,MO,R,M            ,L  )  (         _Os       (X,OP,L),_Mrm(X,MO,R,M            ),_sL(X,L))
#define   _O_r_X(    X,OP     ,R  ,MD,MB,MI,MS    )  (         _O        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS)         )
#define  _OO_r_X(    X,OP     ,R  ,MD,MB,MI,MS    )  (        _OO        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS)         )
#define   _O_r_X_B(  X,OP     ,R  ,MD,MB,MI,MS,B  )  (         _O        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS) ,_B(X,B))
#define   _O_r_X_W(  X,OP     ,R  ,MD,MB,MI,MS,W  )  (         _O        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS) ,_W(X,W))
#define   _O_r_X_L(  X,OP     ,R  ,MD,MB,MI,MS,L  )  (         _O        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS) ,_L(X,L))
#define  _OO_r_X_B(  X,OP     ,R  ,MD,MB,MI,MS,B  )  (        _OO        (X,OP  ),_r_X(X,   R  ,MD,MB,MI,MS) ,_B(X,B))
#define   _Os_r_X_sW(X,OP     ,R  ,MD,MB,MI,MS,W  )  (         _Os       (X,OP,W),_r_X(X,   R  ,MD,MB,MI,MS),_sW(X,W))
#define   _Os_r_X_sL(X,OP     ,R  ,MD,MB,MI,MS,L  )  (         _Os       (X,OP,L),_r_X(X,   R  ,MD,MB,MI,MS),_sL(X,L))
#define   _O_X_B(    X,OP         ,MD,MB,MI,MS,B  )  (         _O_r_X_B  (X,OP           ,0    ,MD,MB,MI,MS       ,B))
#define   _O_X_W(    X,OP         ,MD,MB,MI,MS,W  )  (         _O_r_X_W  (X,OP           ,0    ,MD,MB,MI,MS       ,W))
#define   _O_X_L(    X,OP         ,MD,MB,MI,MS,L  )  (         _O_r_X_L  (X,OP           ,0    ,MD,MB,MI,MS       ,L))
#define  _wO(        X,OP                         )  (_d16(X), _O        (X,OP                                      ))
#define  _wOr(       X,OP,R                       )  (_d16(X), _Or       (X,OP,R                                    ))
#define  _wOr_W(     X,OP,R                   ,W  )  (_d16(X), _Or_W     (X,OP,R                                  ,W))
#define  _wOs_sW(    X,OP                     ,W  )  (_d16(X), _Os_sW    (X,OP                                    ,W))
#define  _wO_Mrm(    X,OP  ,MO,R,M                )  (_d16(X), _O_Mrm    (X,OP          ,MO,R,M                     ))
#define _wOO_Mrm(    X,OP  ,MO,R,M                )  (_d16(X),_OO_Mrm    (X,OP          ,MO,R,M                     ))
#define  _wO_Mrm_B(  X,OP  ,MO,R,M            ,B  )  (_d16(X), _O_Mrm_B  (X,OP          ,MO,R,M                   ,B))
#define _wOO_Mrm_B(  X,OP  ,MO,R,M            ,B  )  (_d16(X),_OO_Mrm_B  (X,OP          ,MO,R,M                   ,B))
#define  _wO_Mrm_W(  X,OP  ,MO,R,M            ,W  )  (_d16(X), _O_Mrm_W  (X,OP          ,MO,R,M                   ,W))
#define  _wOs_Mrm_sW(X,OP  ,MO,R,M            ,W  )  (_d16(X), _Os_Mrm_sW(X,OP          ,MO,R,M                   ,W))
#define  _wO_X_W(    X,OP         ,MD,MB,MI,MS,W  )  (_d16(X), _O_X_W    (X,OP                 ,MD,MB,MI,MS       ,W))
#define  _wO_r_X(    X,OP     ,R  ,MD,MB,MI,MS    )  (_d16(X), _O_r_X    (X,OP             ,R  ,MD,MB,MI,MS         ))
#define _wOO_r_X(    X,OP     ,R  ,MD,MB,MI,MS    )  (_d16(X),_OO_r_X    (X,OP             ,R  ,MD,MB,MI,MS         ))
#define  _wO_r_X_B(  X,OP     ,R  ,MD,MB,MI,MS,B  )  (_d16(X), _O_r_X_B  (X,OP             ,R  ,MD,MB,MI,MS       ,B))
#define _wOO_r_X_B(  X,OP     ,R  ,MD,MB,MI,MS,B  )  (_d16(X),_OO_r_X_B  (X,OP             ,R  ,MD,MB,MI,MS       ,B))
#define  _wO_r_X_W(  X,OP     ,R  ,MD,MB,MI,MS,W  )  (_d16(X), _O_r_X_W  (X,OP             ,R  ,MD,MB,MI,MS       ,W))
#define  _wOs_r_X_sW(X,OP     ,R  ,MD,MB,MI,MS,W  )  (_d16(X), _Os_r_X_sW(X,OP             ,R  ,MD,MB,MI,MS       ,W))

/* +++ fully-qualified intrinsic instructions */

/*                                      _format          Opcd           ,Mod ,r     ,m          ,mem=dsp+sib    ,imm... */
        
#define ADCBrr(RS, RD,X)                  _O_Mrm          (X,0x10           ,_b11,_r1(RS),_r1(RD)                           )
#define ADCBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x12                ,_r1(RD)           ,MD,MB,MI,MS            )
#define ADCBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x10                ,_r1(RS)           ,MD,MB,MI,MS            )
#define ADCBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b010  ,_r1(RD)                   ,_s1(IM))
#define ADCBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b010             ,MD,MB,MI,MS    ,_s1(IM))
        
#define ADCWrr(RS, RD,X)                  _wO_Mrm         (X,0x11           ,_b11,_r2(RS),_r2(RD)                           )
#define ADCWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x13                ,_r2(RD)           ,MD,MB,MI,MS            )
#define ADCWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x11                ,_r2(RS)           ,MD,MB,MI,MS            )
#define ADCWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b010  ,_r2(RD)                   ,_s2(IM))
#define ADCWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b010             ,MD,MB,MI,MS    ,_s2(IM))
        
#define ADCLrr(RS, RD,X)                  _O_Mrm          (X,0x11           ,_b11,_r4(RS),_r4(RD)                           )
#define ADCLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x13                ,_r4(RD)           ,MD,MB,MI,MS            )
#define ADCLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x11                ,_r4(RS)           ,MD,MB,MI,MS            )
#define ADCLir(IM, RD,X)                  _Os_Mrm_sL      (X,0x81           ,_b11,_b010  ,_r4(RD)                   ,IM     )
#define ADCLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL      (X,0x81                ,_b010             ,MD,MB,MI,MS    ,IM     )
        
        
#define ADDBrr(RS, RD,X)                  _O_Mrm          (X,0x00           ,_b11,_r1(RS),_r1(RD)                           )
#define ADDBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x02                ,_r1(RD)           ,MD,MB,MI,MS            )
#define ADDBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x00                ,_r1(RS)           ,MD,MB,MI,MS            )
#define ADDBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b000  ,_r1(RD)                   ,_s1(IM))
#define ADDBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b000             ,MD,MB,MI,MS    ,_s1(IM))
        
#define ADDWrr(RS, RD,X)                  _wO_Mrm         (X,0x01           ,_b11,_r2(RS),_r2(RD)                           )
#define ADDWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x03                ,_r2(RD)           ,MD,MB,MI,MS            )
#define ADDWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x01                ,_r2(RS)           ,MD,MB,MI,MS            )
#define ADDWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b000  ,_r2(RD)                   ,_s2(IM))
#define ADDWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b000             ,MD,MB,MI,MS    ,_s2(IM))
        
#define ADDLrr(RS, RD,X)                  _O_Mrm          (X,0x01           ,_b11,_r4(RS),_r4(RD)                           )
#define ADDLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x03                ,_r4(RD)           ,MD,MB,MI,MS            )
#define ADDLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x01                ,_r4(RS)           ,MD,MB,MI,MS            )
#define ADDLir(IM, RD,X)                  _Os_Mrm_sL      (X,0x81           ,_b11,_b000  ,_r4(RD)                   ,IM     )
#define ADDLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL      (X,0x81                ,_b000             ,MD,MB,MI,MS    ,IM     )
        
        
#define ANDBrr(RS, RD,X)                  _O_Mrm          (X,0x20           ,_b11,_r1(RS),_r1(RD)                           )
#define ANDBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x22                ,_r1(RD)           ,MD,MB,MI,MS            )
#define ANDBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x20                ,_r1(RS)           ,MD,MB,MI,MS            )
#define ANDBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b100  ,_r1(RD)                   ,_s1(IM))
#define ANDBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b100             ,MD,MB,MI,MS    ,_s1(IM))
        
#define ANDWrr(RS, RD,X)                  _wO_Mrm         (X,0x21           ,_b11,_r2(RS),_r2(RD)                           )
#define ANDWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x23                ,_r2(RD)           ,MD,MB,MI,MS            )
#define ANDWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x21                ,_r2(RS)           ,MD,MB,MI,MS            )
#define ANDWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b100  ,_r2(RD)                   ,_s2(IM))
#define ANDWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b100             ,MD,MB,MI,MS    ,_s2(IM))
        
#define ANDLrr(RS, RD,X)                  _O_Mrm          (X,0x21           ,_b11,_r4(RS),_r4(RD)                           )
#define ANDLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x23                ,_r4(RD)           ,MD,MB,MI,MS            )
#define ANDLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x21                ,_r4(RS)           ,MD,MB,MI,MS            )
#define ANDLir(IM, RD,X)                  _Os_Mrm_sL      (X,0x81           ,_b11,_b100  ,_r4(RD)                   ,IM     )
#define ANDLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL      (X,0x81                ,_b100             ,MD,MB,MI,MS    ,IM     )


#define BSWAPLr(R,X)                      _OOr            (X,0x0fc8,_r4(R)                                                  )


#define BTWir(IM,RD,X)                    _wOO_Mrm_B      (X,0x0fba         ,_b11,_b100  ,_r2(RD)                   ,_u1(IM))
#define BTWim(IM,MD,MB,MI,MS,X)           _wOO_r_X_B      (X,0x0fba              ,_b100             ,MD,MB,MI,MS    ,_u1(IM))
#define BTWrr(RS,RD,X)                    _wOO_Mrm        (X,0x0fa3         ,_b11,_r2(RS),_r2(RD)                           )
#define BTWrm(RS,MD,MB,MI,MS,X)           _wOO_r_X        (X,0x0fa3              ,_r2(RS)           ,MD,MB,MI,MS            )

#define BTLir(IM,RD,X)                    _OO_Mrm_B       (X,0x0fba         ,_b11,_b100  ,_r4(RD)                   ,_u1(IM))
#define BTLim(IM,MD,MB,MI,MS,X)           _OO_r_X_B       (X,0x0fba              ,_b100             ,MD,MB,MI,MS    ,_u1(IM))
#define BTLrr(RS,RD,X)                    _OO_Mrm         (X,0x0fa3         ,_b11,_r4(RS),_r4(RD)                           )
#define BTLrm(RS,MD,MB,MI,MS,X)           _OO_r_X         (X,0x0fa3              ,_r4(RS)           ,MD,MB,MI,MS            )


#define BTCWir(IM,RD,X)                   _wOO_Mrm_B      (X,0x0fba         ,_b11,_b111  ,_r2(RD)                   ,_u1(IM))
#define BTCWim(IM,MD,MB,MI,MS,X)          _wOO_r_X_B      (X,0x0fba              ,_b111             ,MD,MB,MI,MS    ,_u1(IM))
#define BTCWrr(RS,RD,X)                   _wOO_Mrm        (X,0x0fbb         ,_b11,_r2(RS),_r2(RD)                           )
#define BTCWrm(RS,MD,MB,MI,MS,X)          _wOO_r_X        (X,0x0fbb              ,_r2(RS)           ,MD,MB,MI,MS            )

#define BTCLir(IM,RD,X)                   _OO_Mrm_B       (X,0x0fba         ,_b11,_b111  ,_r4(RD)                   ,_u1(IM))
#define BTCLim(IM,MD,MB,MI,MS,X)          _OO_r_X_B       (X,0x0fba              ,_b111             ,MD,MB,MI,MS    ,_u1(IM))
#define BTCLrr(RS,RD,X)                   _OO_Mrm         (X,0x0fbb         ,_b11,_r4(RS),_r4(RD)                           )
#define BTCLrm(RS,MD,MB,MI,MS,X)          _OO_r_X         (X,0x0fbb              ,_r4(RS)           ,MD,MB,MI,MS            )


#define BTRWir(IM,RD,X)                   _wOO_Mrm_B      (X,0x0fba         ,_b11,_b110  ,_r2(RD)                   ,_u1(IM))
#define BTRWim(IM,MD,MB,MI,MS,X)          _wOO_r_X_B      (X,0x0fba              ,_b110             ,MD,MB,MI,MS    ,_u1(IM))
#define BTRWrr(RS,RD,X)                   _wOO_Mrm        (X,0x0fb3         ,_b11,_r2(RS),_r2(RD)                           )
#define BTRWrm(RS,MD,MB,MI,MS,X)          _wOO_r_X        (X,0x0fb3              ,_r2(RS)           ,MD,MB,MI,MS            )

#define BTRLir(IM,RD,X)                   _OO_Mrm_B       (X,0x0fba         ,_b11,_b110  ,_r4(RD)                   ,_u1(IM))
#define BTRLim(IM,MD,MB,MI,MS,X)          _OO_r_X_B       (X,0x0fba              ,_b110             ,MD,MB,MI,MS    ,_u1(IM))
#define BTRLrr(RS,RD,X)                   _OO_Mrm         (X,0x0fb3         ,_b11,_r4(RS),_r4(RD)                           )
#define BTRLrm(RS,MD,MB,MI,MS,X)          _OO_r_X         (X,0x0fb3              ,_r4(RS)           ,MD,MB,MI,MS            )


#define BTSWir(IM,RD,X)                   _wOO_Mrm_B      (X,0x0fba         ,_b11,_b101  ,_r2(RD)                   ,_u1(IM))
#define BTSWim(IM,MD,MB,MI,MS,X)          _wOO_r_X_B      (X,0x0fba              ,_b101             ,MD,MB,MI,MS    ,_u1(IM))
#define BTSWrr(RS,RD,X)                   _wOO_Mrm        (X,0x0fab         ,_b11,_r2(RS),_r2(RD)                           )
#define BTSWrm(RS,MD,MB,MI,MS,X)          _wOO_r_X        (X,0x0fab              ,_r2(RS)           ,MD,MB,MI,MS            )

#define BTSLir(IM,RD,X)                   _OO_Mrm_B       (X,0x0fba         ,_b11,_b101  ,_r4(RD)                   ,_u1(IM))
#define BTSLim(IM,MD,MB,MI,MS,X)          _OO_r_X_B       (X,0x0fba              ,_b101             ,MD,MB,MI,MS    ,_u1(IM))
#define BTSLrr(RS,RD,X)                   _OO_Mrm         (X,0x0fab         ,_b11,_r4(RS),_r4(RD)                           )
#define BTSLrm(RS,MD,MB,MI,MS,X)          _OO_r_X         (X,0x0fab              ,_r4(RS)           ,MD,MB,MI,MS            )


#define CALLm(MD,MB,MI,MS,X)              (X,(_r0P(MB) && _r0P(MI)) ? _O_D4 (X,0xe8              ,(MD)                   ) : \
                                          ((            _r0P(MI)) ? _O_Mrm(X,0xff,_b11,_b010,_r4    (MB)               ) : \
                                                                    _O_r_X(X,0xff,     _b010   ,(MD),MB,MI,MS)         ))

#define CBW(X)                           _O              (X,0x98                                                           )
#define CLC(X)                           _O              (X,0xf8                                                           )
#define CLTD(X)                          _O              (X,0x99                                                           )
#define CMC(X)                           _O              (X,0xf5                                                           )


#define CMPBrr(RS, RD,X)                  _O_Mrm          (X,0x38           ,_b11,_r1(RS),_r1(RD)                           )
#define CMPBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x3a                ,_r1(RD)           ,MD,MB,MI,MS            )
#define CMPBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x38                ,_r1(RS)           ,MD,MB,MI,MS            )
#define CMPBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b111  ,_r1(RD)                   ,_s1(IM))
#define CMPBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b111             ,MD,MB,MI,MS    ,_s1(IM))
        
#define CMPWrr(RS, RD,X)                  _wO_Mrm         (X,0x39           ,_b11,_r2(RS),_r2(RD)                           )
#define CMPWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x3b                ,_r2(RD)           ,MD,MB,MI,MS            )
#define CMPWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x39                ,_r2(RS)           ,MD,MB,MI,MS            )
#define CMPWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b111  ,_r2(RD)                   ,_s2(IM))
#define CMPWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b111             ,MD,MB,MI,MS    ,_s2(IM))
        
#define CMPLrr(RS, RD,X)                  _O_Mrm          (X,0x39           ,_b11,_r4(RS),_r4(RD)                           )
#define CMPLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x3b                ,_r4(RD)           ,MD,MB,MI,MS            )
#define CMPLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x39                ,_r4(RS)           ,MD,MB,MI,MS            )
#define CMPLir(IM, RD,X)                  _O_Mrm_L        (X,0x81           ,_b11,_b111  ,_r4(RD)                   ,IM     )
#define CMPLim(IM, MD, MB, MI, MS,X)      _O_r_X_L        (X,0x81                ,_b111             ,MD,MB,MI,MS    ,IM     )
        

#define CWD(X)                            _O              (X,0x99                                                           )


#define CMPXCHGBrr(RS,RD,X)               _OO_Mrm         (X,0x0fb0         ,_b11,_r1(RS),_r1(RD)                           )
#define CMPXCHGBrm(RS,MD,MB,MI,MS,X)      _OO_r_X         (X,0x0fb0              ,_r1(RS)           ,MD,MB,MI,MS            )

#define CMPXCHGWrr(RS,RD,X)               _wOO_Mrm        (X,0x0fb1         ,_b11,_r2(RS),_r2(RD)                           )
#define CMPXCHGWrm(RS,MD,MB,MI,MS,X)      _wOO_r_X        (X,0x0fb1              ,_r2(RS)           ,MD,MB,MI,MS            )

#define CMPXCHGLrr(RS,RD,X)               _OO_Mrm         (X,0x0fb1         ,_b11,_r4(RS),_r4(RD)                           )
#define CMPXCHGLrm(RS,MD,MB,MI,MS,X)      _OO_r_X         (X,0x0fb1              ,_r4(RS)           ,MD,MB,MI,MS            )


#define DECBr(RD,X)                       _O_Mrm          (X,0xfe           ,_b11,_b001  ,_r1(RD)                           )
#define DECBm(MD,MB,MI,MS,X)              _O_r_X          (X,0xfe                ,_b001             ,MD,MB,MI,MS            )

#define DECWr(RD,X)                       _wOr            (X,0x48,_r2(RD)                                                   )
#define DECWm(MD,MB,MI,MS,X)              _wO_r_X         (X,0xff                ,_b001             ,MD,MB,MI,MS            )

#define DECLr(RD,X)                       _Or             (X,0x48,_r4(RD)                                                   )
#define DECLm(MD,MB,MI,MS,X)              _O_r_X          (X,0xff                ,_b001             ,MD,MB,MI,MS            )


#define DIVBrr(RS,RD,X)           ( _rAL (RD) +   _O_Mrm  (X,0xf6           ,_b11,_b110  ,_r1(RS)                           ) )
#define DIVBmr(MD,MB,MI,MS,RD,X)  ( _rAL (RD) +   _O_r_X  (X,0xf6                ,_b110             ,MD,MB,MI,MS            ) )

#define DIVWrr(RS,RD,X)           ( _rAX (RD) +   _wO_Mrm (X,0xf7          ,_b11,_b110  ,_r2(RS)                           ) )
#define DIVWmr(MD,MB,MI,MS,RD,X)  ( _rAX (RD) +   _wO_r_X (X,0xf7                 ,_b110             ,MD,MB,MI,MS            ) )

#define DIVLrr(RS,RD,X)           ( _rEAX(RD) +   _O_Mrm  (X,0xf7           ,_b11,_b110  ,_r4(RS)                           ) )
#define DIVLmr(MD,MB,MI,MS,RD,X)  ( _rEAX(RD) +   _O_r_X  (X,0xf7                ,_b110             ,MD,MB,MI,MS            ) )


#define ENTERii(W, B,X)                   _O_W_B          (X,0xc8                                             ,_s2(W),_s1(B))
#define HLT(X)                            _O              (X,0xf4                                                           )


#define IDIVBrr(RS,RD,X)          ( _rAL (RD) +   _O_Mrm  (X,0xf6           ,_b11,_b111  ,_r1(RS)                           ) )
#define IDIVBmr(MD,MB,MI,MS,RD,X) ( _rAL (RD) +   _O_r_X  (X,0xf6                ,_b111             ,MD,MB,MI,MS            ) )

#define IDIVWrr(RS,RD,X)          ( _rAX (RD) +   _wO_Mrm (X,0xf7           ,_b11,_b111  ,_r2(RS)                           ) )
#define IDIVWmr(MD,MB,MI,MS,RD,X) ( _rAX (RD) +   _wO_r_X (X,0xf7                ,_b111             ,MD,MB,MI,MS            ) )

#define IDIVLrr(RS,RD,X)          ( _rEAX(RD) +   _O_Mrm  (X,0xf7           ,_b11,_b111  ,_r4(RS)                           ) )
#define IDIVLmr(MD,MB,MI,MS,RD,X) ( _rEAX(RD) +   _O_r_X  (X,0xf7                ,_b111             ,MD,MB,MI,MS            ) )


#define IMULWrr(RS,RD,X)                  _wOO_Mrm        (X,0x0faf         ,_b11,_r2(RS),_r2(RD)                           )
#define IMULWmr(MD,MB,MI,MS,RD,X)         _wOO_r_X        (X,0x0faf              ,_r2(RD)           ,MD,MB,MI,MS            )
#define IMULWirr(IM,RS,RD,X)              _wOs_Mrm_sW     (X,0x69           ,_b11,_r2(RS),_r2(RD)                   ,IM     )
#define IMULWimr(IM,MD,MB,MI,MS,RD,X)     _wOs_r_X_sW     (X,0x69                ,_r2(RD)           ,MD,MB,MI,MS    ,IM     )

#define IMULLrr(RS,RD,X)                  _OO_Mrm         (X,0x0faf         ,_b11,_r4(RD),_r4(RS)                           )
#define IMULLmr(MD,MB,MI,MS,RD,X)         _OO_r_X         (X,0x0faf              ,_r4(RD)           ,MD,MB,MI,MS            )
#define IMULLirr(IM,RS,RD,X)              _Os_Mrm_sL      (X,0x69           ,_b11,_r4(RS),_r4(RD)                   ,IM     )
#define IMULLimr(IM,MD,MB,MI,MS,RD,X)     _Os_r_X_sL      (X,0x69                ,_r4(RD)           ,MD,MB,MI,MS    ,IM     )


#define INCBr(RD,X)                       _O_Mrm          (X,0xfe           ,_b11,_b000  ,_r1(RD)                           )
#define INCBm(MD,MB,MI,MS,X)              _O_r_X          (X,0xfe                ,_b000             ,MD,MB,MI,MS            )

#define INCWr(RD,X)                       _wOr            (X,0x40,_r2(RD)                                                   )
#define INCWm(MD,MB,MI,MS,X)              _wO_r_X         (X,0xff                ,_b000             ,MD,MB,MI,MS            )

#define INCLr(RD,X)                       _Or             (X,0x40,_r4(RD)                                                   )
#define INCLm(MD,MB,MI,MS,X)              _O_r_X          (X,0xff                ,_b000             ,MD,MB,MI,MS            )


#define INVD(X)                          _OO             (X,0x0f08                                                         )
#define INVLPGm(MD, MB, MI, MS,X)         _OO_r_X         (X,0x0f01              ,_b111             ,MD,MB,MI,MS            )


#define JCCSim(CC,D,B,I,S,X)              ((_r0P(B) && _r0P(I)) ? _O_D1   (X,0x70|(CC)              ,(D)                    ) : \
                                                                ASMFAIL("illegal mode in conditional jump"))

#define JOSm(D,B,I,S,X)                   JCCSim(0x0,D,B,I,S,X)
#define JNOSm(D,B,I,S,X)                  JCCSim(0x1,D,B,I,S,X)
#define JBSm(D,B,I,S,X)                   JCCSim(0x2,D,B,I,S,X)
#define JNAESm(D,B,I,S,X)                 JCCSim(0x2,D,B,I,S,X)
#define JNBSm(D,B,I,S,X)                  JCCSim(0x3,D,B,I,S,X)
#define JAESm(D,B,I,S,X)                  JCCSim(0x3,D,B,I,S,X)
#define JESm(D,B,I,S,X)                   JCCSim(0x4,D,B,I,S,X)
#define JZSm(D,B,I,S,X)                   JCCSim(0x4,D,B,I,S,X)
#define JNESm(D,B,I,S,X)                  JCCSim(0x5,D,B,I,S,X)
#define JNZSm(D,B,I,S,X)                  JCCSim(0x5,D,B,I,S,X)
#define JBESm(D,B,I,S,X)                  JCCSim(0x6,D,B,I,S,X)
#define JNASm(D,B,I,S,X)                  JCCSim(0x6,D,B,I,S,X)
#define JNBESm(D,B,I,S,X)                 JCCSim(0x7,D,B,I,S,X)
#define JASm(D,B,I,S,X)                   JCCSim(0x7,D,B,I,S,X)
#define JSSm(D,B,I,S,X)                   JCCSim(0x8,D,B,I,S,X)
#define JNSSm(D,B,I,S,X)                  JCCSim(0x9,D,B,I,S,X)
#define JPSm(D,B,I,S,X)                   JCCSim(0xa,D,B,I,S,X)
#define JPESm(D,B,I,S,X)                  JCCSim(0xa,D,B,I,S,X)
#define JNPSm(D,B,I,S,X)                  JCCSim(0xb,D,B,I,S,X)
#define JPOSm(D,B,I,S,X)                  JCCSim(0xb,D,B,I,S,X)
#define JLSm(D,B,I,S,X)                   JCCSim(0xc,D,B,I,S,X)
#define JNGESm(D,B,I,S,X)                 JCCSim(0xc,D,B,I,S,X)
#define JNLSm(D,B,I,S,X)                  JCCSim(0xd,D,B,I,S,X)
#define JGESm(D,B,I,S,X)                  JCCSim(0xd,D,B,I,S,X)
#define JLESm(D,B,I,S,X)                  JCCSim(0xe,D,B,I,S,X)
#define JNGSm(D,B,I,S,X)                  JCCSim(0xe,D,B,I,S,X)
#define JNLESm(D,B,I,S,X)                 JCCSim(0xf,D,B,I,S,X)
#define JGSm(D,B,I,S,X)                   JCCSim(0xf,D,B,I,S,X)

#define JCCim(CC,D,B,I,S,X)               ((_r0P(B) && _r0P(I)) ? _OO_D4  (X,0x0f80|(CC)            ,(D)                    ) : \
                                                                ASMFAIL("illegal mode in conditional jump"))

#define JOm(D,B,I,S,X)                    JCCim(0x0,D,B,I,S,X)
#define JNOm(D,B,I,S,X)                   JCCim(0x1,D,B,I,S,X)
#define JBm(D,B,I,S,X)                    JCCim(0x2,D,B,I,S,X)
#define JNAEm(D,B,I,S,X)                  JCCim(0x2,D,B,I,S,X)
#define JNBm(D,B,I,S,X)                   JCCim(0x3,D,B,I,S,X)
#define JAEm(D,B,I,S,X)                   JCCim(0x3,D,B,I,S,X)
#define JEm(D,B,I,S,X)                    JCCim(0x4,D,B,I,S,X)
#define JZm(D,B,I,S,X)                    JCCim(0x4,D,B,I,S,X)
#define JNEm(D,B,I,S,X)                   JCCim(0x5,D,B,I,S,X)
#define JNZm(D,B,I,S,X)                   JCCim(0x5,D,B,I,S,X)
#define JBEm(D,B,I,S,X)                   JCCim(0x6,D,B,I,S,X)
#define JNAm(D,B,I,S,X)                   JCCim(0x6,D,B,I,S,X)
#define JNBEm(D,B,I,S,X)                  JCCim(0x7,D,B,I,S,X)
#define JAm(D,B,I,S,X)                    JCCim(0x7,D,B,I,S,X)
#define JSm(D,B,I,S,X)                    JCCim(0x8,D,B,I,S,X)
#define JNSm(D,B,I,S,X)                   JCCim(0x9,D,B,I,S,X)
#define JPm(D,B,I,S,X)                    JCCim(0xa,D,B,I,S,X)
#define JPEm(D,B,I,S,X)                   JCCim(0xa,D,B,I,S,X)
#define JNPm(D,B,I,S,X)                   JCCim(0xb,D,B,I,S,X)
#define JPOm(D,B,I,S,X)                   JCCim(0xb,D,B,I,S,X)
#define JLm(D,B,I,S,X)                    JCCim(0xc,D,B,I,S,X)
#define JNGEm(D,B,I,S,X)                  JCCim(0xc,D,B,I,S,X)
#define JNLm(D,B,I,S,X)                   JCCim(0xd,D,B,I,S,X)
#define JGEm(D,B,I,S,X)                   JCCim(0xd,D,B,I,S,X)
#define JLEm(D,B,I,S,X)                   JCCim(0xe,D,B,I,S,X)
#define JNGm(D,B,I,S,X)                   JCCim(0xe,D,B,I,S,X)
#define JNLEm(D,B,I,S,X)                  JCCim(0xf,D,B,I,S,X)
#define JGm(D,B,I,S,X)                    JCCim(0xf,D,B,I,S,X)


#define JMPSm(D,B,I,S,X)                  ((_r0P(B) && _r0P(I)) ? _O_D1   (X,0xeb                   ,(D)                    ) : \
                                                                ASMFAIL("illegal mode in short jump"))

#define JMPm(D,B,I,S,X)                   ((_r0P(B) && _r0P(I)) ? _O_D4   (X,0xe9                   ,(D)                    ) : \
                                                   ((_r0P(I)) ? _O_Mrm  (X,0xff   ,_b11,_b100,_r4(B)                      ) : \
                                                                _O_r_X  (X,0xff        ,_b100     ,(D),B,I,S              ) ))


#define LAHF(X)                           _O              (X,0x9f                                                           )
#define LEALmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x8d                ,_r4(RD)           ,MD,MB,MI,MS            )
#define LEAVE(X)                          _O              (X,0xc9                                                           )

        
#define LMSWr(RS,X)                       _OO_Mrm         (X,0x0f01         ,_b11,_b110,_r4(RS)                             )
#define LMSWm(MD,MB,MI,MS,X)              _OO_r_X         (X,0x0f01              ,_b110             ,MD,MB,MI,MS            )

#define LOOPm(MD,MB,MI,MS,X)              ((_r0P(MB) && _r0P(MI)) ? _O_D1 (X,0xe2                   ,MD                     ) : \
                                                                  ASMFAIL("illegal mode in loop"))

#define LOOPEm(MD,MB,MI,MS,X)             ((_r0P(MB) && _r0P(MI)) ? _O_D1 (X,0xe1                   ,MD                     ) : \
                                                                  ASMFAIL("illegal mode in loope"))

#define LOOPZm(MD,MB,MI,MS,X)             ((_r0P(MB) && _r0P(MI)) ? _O_D1 (X,0xe1                   ,MD                     ) : \
                                                                  ASMFAIL("illegal mode in loopz"))

#define LOOPNEm(MD,MB,MI,MS,X)            ((_r0P(MB) && _r0P(MI)) ? _O_D1 (X,0xe0                   ,MD                     ) : \
                                                                  ASMFAIL("illegal mode in loopne"))

#define LOOPNZm(MD,MB,MI,MS,X)            ((_r0P(MB) && _r0P(MI)) ? _O_D1 (X,0xe0                   ,MD                     ) : \
                                                                  ASMFAIL("illegal mode in loopnz"))


#define MOVBrr(RS, RD,X)                  _O_Mrm          (X,0x80           ,_b11,_r1(RS),_r1(RD)                           )
#define MOVBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x8a                ,_r1(RD)           ,MD,MB,MI,MS            )
#define MOVBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x88                ,_r1(RS)           ,MD,MB,MI,MS            )
#define MOVBir(IM,  R,X)                  _Or_B           (X,0xb0,_r1(R)                                            ,_s1(IM))
#define MOVBim(IM, MD, MB, MI, MS,X)      _O_X_B          (X,0xc6                                   ,MD,MB,MI,MS    ,_s1(IM))

#define MOVWrr(RS, RD,X)                  _wO_Mrm         (X,0x89           ,_b11,_r2(RS),_r2(RD)                           )
#define MOVWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x8b                ,_r2(RD)           ,MD,MB,MI,MS            )
#define MOVWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x89                ,_r2(RS)           ,MD,MB,MI,MS            )
#define MOVWir(IM,  R,X)                  _wOr_W          (X,0xb8,_r2(R)                                            ,_s2(IM))
#define MOVWim(IM, MD, MB, MI, MS,X)      _wO_X_W         (X,0xc7                                   ,MD,MB,MI,MS    ,_s2(IM))

#define MOVLrr(RS, RD,X)                  _O_Mrm          (X,0x89           ,_b11,_r4(RS),_r4(RD)                           )
#define MOVLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x8b                ,_r4(RD)           ,MD,MB,MI,MS            )
#define MOVLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x89                ,_r4(RS)           ,MD,MB,MI,MS            )
#define MOVLir(IM,  R,X)                  _Or_L           (X,0xb8,_r4(R)                                            ,IM     )
#define MOVLim(IM, MD, MB, MI, MS,X)      _O_X_L          (X,0xc7                                   ,MD,MB,MI,MS    ,IM     )

#define MOVSBLrr(RS,RD,X)                 _OO_Mrm         (X,0x0fbe         ,_b11,_r1(RS),_r4(RD)                           )
#define MOVSBLmr(MD,MB,MI,MS,RD,X)        _OO_r_X         (X,0x0fbe              ,_r4(RD)           ,MD,MB,MI,MS            )

#define MULBrr(RS,RD,X)           ( _rAL (RD) +   _O_Mrm  (X,0xf6           ,_b11,_b100  ,_r1(RS)                           ) )
#define MULBmr(MD,MB,MI,MS,RD,X)  ( _rAL (RD) +   _O_r_X  (X,0xf6                ,_b100             ,MD,MB,MI,MS            ) )

#define MULWrr(RS,RD,X)           ( _rAX (RD) +   _wO_Mrm (X,0xf7           ,_b11,_b100  ,_r2(RS)                           ) )
#define MULWmr(MD,MB,MI,MS,RD,X)  ( _rAX (RD) +   _wO_r_X (X,0xf7                ,_b100             ,MD,MB,MI,MS            ) )

#define MULLrr(RS,RD,X)           ( _rEAX(RD) +   _O_Mrm  (X,0xf7           ,_b11,_b100  ,_r4(RS)                           ) )
#define MULLmr(MD,MB,MI,MS,RD,X)  ( _rEAX(RD) +   _O_r_X  (X,0xf7                ,_b100             ,MD,MB,MI,MS            ) )


#define NEGBr(RD,X)                       _O_Mrm          (X,0xf6           ,_b11,_b011  ,_r1(RD)                           )
#define NEGBm(MD,MB,MI,MS,X)              _O_r_X          (X,0xf6                ,_b011             ,MD,MB,MI,MS            )

#define NEGWr(RD,X)                       _wO_Mrm         (X,0xf7           ,_b11,_b011  ,_r2(RD)                           )
#define NEGWm(MD,MB,MI,MS,X)              _wO_r_X         (X,0xf7                ,_b011             ,MD,MB,MI,MS            )

#define NEGLr(RD,X)                       _O_Mrm          (X,0xf7           ,_b11,_b011  ,_r4(RD)                           )
#define NEGLm(MD,MB,MI,MS,X)              _O_r_X          (X,0xf7                ,_b011             ,MD,MB,MI,MS            )


#define NOP(X)                            _O              (X,0x90                                                           )


#define NOTBr(RD,X)                       _O_Mrm          (X,0xf6           ,_b11,_b010  ,_r1(RD)                           )
#define NOTBm(MD,MB,MI,MS,X)              _O_r_X          (X,0xf6                ,_b010             ,MD,MB,MI,MS            )

#define NOTWr(RD,X)                       _wO_Mrm         (X,0xf7           ,_b11,_b010  ,_r2(RD)                           )
#define NOTWm(MD,MB,MI,MS,X)              _wO_r_X         (X,0xf7                ,_b010             ,MD,MB,MI,MS            )

#define NOTLr(RD,X)                       _O_Mrm          (X,0xf7           ,_b11,_b010  ,_r4(RD)                           )
#define NOTLm(MD,MB,MI,MS,X)              _O_r_X          (X,0xf7                ,_b010             ,MD,MB,MI,MS            )


#define ORBrr(RS, RD,X)                   _O_Mrm          (X,0x08           ,_b11,_r1(RS),_r1(RD)                           )
#define ORBmr(MD, MB, MI, MS, RD,X)       _O_r_X          (X,0x0a                ,_r1(RD)           ,MD,MB,MI,MS            )
#define ORBrm(RS, MD, MB, MI, MS,X)       _O_r_X          (X,0x08                ,_r1(RS)           ,MD,MB,MI,MS            )
#define ORBir(IM, RD,X)                   _O_Mrm_B        (X,0x80           ,_b11,_b001  ,_r1(RD)                   ,_s1(IM))
#define ORBim(IM, MD, MB, MI, MS,X)       _O_r_X_B        (X,0x80                ,_b001             ,MD,MB,MI,MS    ,_s1(IM))
        
#define ORWrr(RS, RD,X)                   _wO_Mrm         (X,0x09           ,_b11,_r2(RS),_r2(RD)                           )
#define ORWmr(MD, MB, MI, MS, RD,X)       _wO_r_X         (X,0x0b                ,_r2(RD)           ,MD,MB,MI,MS            )
#define ORWrm(RS, MD, MB, MI, MS,X)       _wO_r_X         (X,0x09                ,_r2(RS)           ,MD,MB,MI,MS            )
#define ORWir(IM, RD,X)                   _wOs_Mrm_sW     (X,0x81           ,_b11,_b001  ,_r2(RD)                   ,_s2(IM))
#define ORWim(IM, MD, MB, MI, MS,X)       _wOs_r_X_sW     (X,0x81                ,_b001             ,MD,MB,MI,MS    ,_s2(IM))
        
#define ORLrr(RS, RD,X)                   _O_Mrm          (X,0x09           ,_b11,_r4(RS),_r4(RD)                           )
#define ORLmr(MD, MB, MI, MS, RD,X)       _O_r_X          (X,0x0b                ,_r4(RD)           ,MD,MB,MI,MS            )
#define ORLrm(RS, MD, MB, MI, MS,X)       _O_r_X          (X,0x09                ,_r4(RS)           ,MD,MB,MI,MS            )
#define ORLir(IM, RD,X)                   _Os_Mrm_sL      (X,0x81           ,_b11,_b001  ,_r4(RD)                   ,IM     )
#define ORLim(IM, MD, MB, MI, MS,X)       _Os_r_X_sL      (X,0x81                ,_b001             ,MD,MB,MI,MS    ,IM     )


#define POPWr(RD,X)                       _wOr            (X,0x58,_r2(RD)                                                   )
#define POPWm(MD,MB,MI,MS,X)              _wO_r_X         (X,0x8f                ,_b000             ,MD,MB,MI,MS            )

#define POPLr(RD,X)                       _Or             (X,0x58,_r4(RD)                                                   )
#define POPLm(MD,MB,MI,MS,X)              _O_r_X          (X,0x8f                ,_b000             ,MD,MB,MI,MS            )


#define POPA(X)                           _wO             (X,0x61                                                           )
#define POPAD(X)                          _O              (X,0x61                                                           )

#define POPF(X)                           _wO             (X,0x9d                                                           )
#define POPFD(X)                          _O              (X,0x9d                                                           )


#define PUSHWr(R,X)                       _wOr            (X,0x50,_r2(R)                                                    )
#define PUSHWm(MD,MB,MI,MS,X)             _wO_r_X         (X,0xff                ,_b110             ,MD,MB,MI,MS            )
#define PUSHWi(IM,X)                      _wOs_sW         (X,0x68                                                   ,IM     )

#define PUSHLr(R,X)                       _Or             (X,0x50,_r4(R)                                                    )
#define PUSHLm(MD,MB,MI,MS,X)             _O_r_X          (X,0xff                ,_b110             ,MD,MB,MI,MS            )
#define PUSHLi(IM,X)                      _Os_sL          (X,0x68                                                   ,IM     )


#define PUSHA(X)                          _wO             (X,0x60                                                           )
#define PUSHAD(X)                         _O              (X,0x60                                                           )

#define PUSHF(X)                          _O              (X,0x9c                                                           )
#define PUSHFD(X)                         _wO             (X,0x9c                                                           )

#define RET(X)                            _O              (X,0xc3                                                           )
#define RETi(IM,X)                        _O_W            (X,0xc2                                                   ,_s2(IM))


#define ROLBir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd0   ,_b11,_b000,_r1(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc0   ,_b11,_b000,_r1(RD)                     ,_u1(IM) ) )
#define ROLBim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd0        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc0        ,_b000             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define ROLBrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd2   ,_b11,_b000,_r1(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define ROLBrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd2        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define ROLWir(IM,RD,X)           (((IM)==1) ?    _wO_Mrm         (X,0xd1   ,_b11,_b000,_r2(RD)                             ) : \
                                                  _wO_Mrm_B       (X,0xc1   ,_b11,_b000,_r2(RD)                     ,_u1(IM) ) )
#define ROLWim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _wO_r_X         (X,0xd1        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  _wO_r_X_B       (X,0xc1        ,_b000             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define ROLWrr(RS,RD,X)           (((RS)==_CL) ?  _wO_Mrm         (X,0xd3   ,_b11,_b000,_r2(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )
#define ROLWrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _wO_r_X         (X,0xd3        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )

#define ROLLir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd1   ,_b11,_b000,_r4(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc1   ,_b11,_b000,_r4(RD)                     ,_u1(IM) ) )
#define ROLLim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd1        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc1        ,_b000             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define ROLLrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd3   ,_b11,_b000,_r4(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define ROLLrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd3        ,_b000             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )


#define RORBir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd0   ,_b11,_b001,_r1(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc0   ,_b11,_b001,_r1(RD)                     ,_u1(IM) ) )
#define RORBim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd0        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc0        ,_b001             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define RORBrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd2   ,_b11,_b001,_r1(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define RORBrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd2        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define RORWir(IM,RD,X)           (((IM)==1) ?    _wO_Mrm         (X,0xd1   ,_b11,_b001,_r2(RD)                             ) : \
                                                  _wO_Mrm_B       (X,0xc1   ,_b11,_b001,_r2(RD)                     ,_u1(IM) ) )
#define RORWim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _wO_r_X         (X,0xd1        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  _wO_r_X_B       (X,0xc1        ,_b001             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define RORWrr(RS,RD,X)           (((RS)==_CL) ?  _wO_Mrm         (X,0xd3   ,_b11,_b001,_r2(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )
#define RORWrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _wO_r_X         (X,0xd3        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )

#define RORLir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd1   ,_b11,_b001,_r4(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc1   ,_b11,_b001,_r4(RD)                     ,_u1(IM) ) )
#define RORLim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd1        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc1        ,_b001             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define RORLrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd3   ,_b11,_b001,_r4(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define RORLrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd3        ,_b001             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )


#define SAHF(X)                                   _O              (X,0x9e                                                           )


#define SARBir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd0   ,_b11,_b111,_r1(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc0   ,_b11,_b111,_r1(RD)                     ,_u1(IM) ) )
#define SARBim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd0        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc0        ,_b111             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SARBrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd2   ,_b11,_b111,_r1(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SARBrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd2        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define SARWir(IM,RD,X)           (((IM)==1) ?    _wO_Mrm         (X,0xd1   ,_b11,_b111,_r2(RD)                             ) : \
                                                  _wO_Mrm_B       (X,0xc1   ,_b11,_b111,_r2(RD)                     ,_u1(IM) ) )
#define SARWim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _wO_r_X         (X,0xd1        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  _wO_r_X_B       (X,0xc1        ,_b111             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SARWrr(RS,RD,X)           (((RS)==_CL) ?  _wO_Mrm         (X,0xd3   ,_b11,_b111,_r2(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )
#define SARWrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _wO_r_X         (X,0xd3        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )

#define SARLir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd1   ,_b11,_b111,_r4(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc1   ,_b11,_b111,_r4(RD)                     ,_u1(IM) ) )
#define SARLim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd1        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc1        ,_b111             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SARLrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd3   ,_b11,_b111,_r4(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SARLrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd3        ,_b111             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )


#define SBBBrr(RS, RD,X)                  _O_Mrm                  (X,0x18           ,_b11,_r1(RS),_r1(RD)                           )
#define SBBBmr(MD, MB, MI, MS, RD,X)      _O_r_X                  (X,0x1a                ,_r1(RD)           ,MD,MB,MI,MS            )
#define SBBBrm(RS, MD, MB, MI, MS,X)      _O_r_X                  (X,0x18                ,_r1(RS)           ,MD,MB,MI,MS            )
#define SBBBir(IM, RD,X)                  _O_Mrm_B                (X,0x80           ,_b11,_b011  ,_r1(RD)                   ,_s1(IM))
#define SBBBim(IM, MD, MB, MI, MS,X)      _O_r_X_B                (X,0x80                ,_b011             ,MD,MB,MI,MS    ,_s1(IM))
        
#define SBBWrr(RS, RD,X)                  _wO_Mrm                 (X,0x19           ,_b11,_r2(RS),_r2(RD)                           )
#define SBBWmr(MD, MB, MI, MS, RD,X)      _wO_r_X                 (X,0x1b                ,_r2(RD)           ,MD,MB,MI,MS            )
#define SBBWrm(RS, MD, MB, MI, MS,X)      _wO_r_X                 (X,0x19                ,_r2(RS)           ,MD,MB,MI,MS            )
#define SBBWir(IM, RD,X)                  _wOs_Mrm_sW             (X,0x81           ,_b11,_b011  ,_r2(RD)                   ,_s2(IM))
#define SBBWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW             (X,0x81                ,_b011             ,MD,MB,MI,MS    ,_s2(IM))
        
#define SBBLrr(RS, RD,X)                  _O_Mrm                  (X,0x19           ,_b11,_r4(RS),_r4(RD)                           )
#define SBBLmr(MD, MB, MI, MS, RD,X)      _O_r_X                  (X,0x1b                ,_r4(RD)           ,MD,MB,MI,MS            )
#define SBBLrm(RS, MD, MB, MI, MS,X)      _O_r_X                  (X,0x19                ,_r4(RS)           ,MD,MB,MI,MS            )
#define SBBLir(IM, RD,X)                  _Os_Mrm_sL              (X,0x81           ,_b11,_b011  ,_r4(RD)                   ,IM     )
#define SBBLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL              (X,0x81                ,_b011             ,MD,MB,MI,MS    ,IM     )


#define SETCCir(CC,RD,X)                  _OO_Mrm         (X,0x0f90|(CC)    ,_b11,_b000,_r1(RD)                             )

#define SETOr(RD,X)                       SETCCir(0x0,RD,X)
#define SETNOr(RD,X)                      SETCCir(0x1,RD,X)
#define SETBr(RD,X)                       SETCCir(0x2,RD,X)
#define SETNAEr(RD,X)                     SETCCir(0x2,RD,X)
#define SETNBr(RD,X)                      SETCCir(0x3,RD,X)
#define SETAEr(RD,X)                      SETCCir(0x3,RD,X)
#define SETEr(RD,X)                       SETCCir(0x4,RD,X)
#define SETZr(RD,X)                       SETCCir(0x4,RD,X)
#define SETNEr(RD,X)                      SETCCir(0x5,RD,X)
#define SETNZr(RD,X)                      SETCCir(0x5,RD,X)
#define SETBEr(RD,X)                      SETCCir(0x6,RD,X)
#define SETNAr(RD,X)                      SETCCir(0x6,RD,X)
#define SETNBEr(RD,X)                     SETCCir(0x7,RD,X)
#define SETAr(RD,X)                       SETCCir(0x7,RD,X)
#define SETSr(RD,X)                       SETCCir(0x8,RD,X)
#define SETNSr(RD,X)                      SETCCir(0x9,RD,X)
#define SETPr(RD,X)                       SETCCir(0xa,RD,X)
#define SETPEr(RD,X)                      SETCCir(0xa,RD,X)
#define SETNPr(RD,X)                      SETCCir(0xb,RD,X)
#define SETPOr(RD,X)                      SETCCir(0xb,RD,X)
#define SETLr(RD,X)                       SETCCir(0xc,RD,X)
#define SETNGEr(RD,X)                     SETCCir(0xc,RD,X)
#define SETNLr(RD,X)                      SETCCir(0xd,RD,X)
#define SETGEr(RD,X)                      SETCCir(0xd,RD,X)
#define SETLEr(RD,X)                      SETCCir(0xe,RD,X)
#define SETNGr(RD,X)                      SETCCir(0xe,RD,X)
#define SETNLEr(RD,X)                     SETCCir(0xf,RD,X)
#define SETGr(RD,X)                       SETCCir(0xf,RD,X)

#define SETCCim(CC,MD,MB,MI,MS,X)         _OO_r_X         (X,0x0f90|(CC)         ,_b000             ,MD,MB,MI,MS            )

#define SETOm(D,B,I,S,X)                  SETCCim(0x0,D,B,I,S,X)
#define SETNOm(D,B,I,S,X)                 SETCCim(0x1,D,B,I,S,X)
#define SETBm(D,B,I,S,X)                  SETCCim(0x2,D,B,I,S,X)
#define SETNAEm(D,B,I,S,X)                SETCCim(0x2,D,B,I,S,X)
#define SETNBm(D,B,I,S,X)                 SETCCim(0x3,D,B,I,S,X)
#define SETAEm(D,B,I,S,X)                 SETCCim(0x3,D,B,I,S,X)
#define SETEm(D,B,I,S,X)                  SETCCim(0x4,D,B,I,S,X)
#define SETZm(D,B,I,S,X)                  SETCCim(0x4,D,B,I,S,X)
#define SETNEm(D,B,I,S,X)                 SETCCim(0x5,D,B,I,S,X)
#define SETNZm(D,B,I,S,X)                 SETCCim(0x5,D,B,I,S,X)
#define SETBEm(D,B,I,S,X)                 SETCCim(0x6,D,B,I,S,X)
#define SETNAm(D,B,I,S,X)                 SETCCim(0x6,D,B,I,S,X)
#define SETNBEm(D,B,I,S,X)                SETCCim(0x7,D,B,I,S,X)
#define SETAm(D,B,I,S,X)                  SETCCim(0x7,D,B,I,S,X)
#define SETSm(D,B,I,S,X)                  SETCCim(0x8,D,B,I,S,X)
#define SETNSm(D,B,I,S,X)                 SETCCim(0x9,D,B,I,S,X)
#define SETPm(D,B,I,S,X)                  SETCCim(0xa,D,B,I,S,X)
#define SETPEm(D,B,I,S,X)                 SETCCim(0xa,D,B,I,S,X)
#define SETNPm(D,B,I,S,X)                 SETCCim(0xb,D,B,I,S,X)
#define SETPOm(D,B,I,S,X)                 SETCCim(0xb,D,B,I,S,X)
#define SETLm(D,B,I,S,X)                  SETCCim(0xc,D,B,I,S,X)
#define SETNGEm(D,B,I,S,X)                SETCCim(0xc,D,B,I,S,X)
#define SETNLm(D,B,I,S,X)                 SETCCim(0xd,D,B,I,S,X)
#define SETGEm(D,B,I,S,X)                 SETCCim(0xd,D,B,I,S,X)
#define SETLEm(D,B,I,S,X)                 SETCCim(0xe,D,B,I,S,X)
#define SETNGm(D,B,I,S,X)                 SETCCim(0xe,D,B,I,S,X)
#define SETNLEm(D,B,I,S,X)                SETCCim(0xf,D,B,I,S,X)
#define SETGm(D,B,I,S,X)                  SETCCim(0xf,D,B,I,S,X)


#define SHLBir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd0   ,_b11,_b100,_r1(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc0   ,_b11,_b100,_r1(RD)                     ,_u1(IM) ) )
#define SHLBim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd0        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc0        ,_b100             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHLBrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd2   ,_b11,_b100,_r1(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHLBrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd2        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define SHLWir(IM,RD,X)           (((IM)==1) ?    _wO_Mrm         (X,0xd1   ,_b11,_b100,_r2(RD)                             ) : \
                                                  _wO_Mrm_B       (X,0xc1   ,_b11,_b100,_r2(RD)                     ,_u1(IM) ) )
#define SHLWim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _wO_r_X         (X,0xd1        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  _wO_r_X_B       (X,0xc1        ,_b100             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHLWrr(RS,RD,X)           (((RS)==_CL) ?  _wO_Mrm         (X,0xd3   ,_b11,_b100,_r2(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHLWrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _wO_r_X         (X,0xd3        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                                   ) )

#define SHLLir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd1   ,_b11,_b100,_r4(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc1   ,_b11,_b100,_r4(RD)                     ,_u1(IM) ) )
#define SHLLim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd1        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc1        ,_b100             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHLLrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd3   ,_b11,_b100,_r4(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHLLrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd3        ,_b100             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )


#define SHRBir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd0   ,_b11,_b101,_r1(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc0   ,_b11,_b101,_r1(RD)                     ,_u1(IM) ) )
#define SHRBim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd0        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc0        ,_b101             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHRBrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd2   ,_b11,_b101,_r1(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHRBrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd2        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define SHRWir(IM,RD,X)           (((IM)==1) ?    _wO_Mrm         (X,0xd1   ,_b11,_b101,_r2(RD)                             ) : \
                                                  _wO_Mrm_B       (X,0xc1   ,_b11,_b101,_r2(RD)                     ,_u1(IM) ) )
#define SHRWim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _wO_r_X         (X,0xd1        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  _wO_r_X_B       (X,0xc1        ,_b101             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHRWrr(RS,RD,X)           (((RS)==_CL) ?  _wO_Mrm         (X,0xd3   ,_b11,_b101,_r2(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHRWrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _wO_r_X         (X,0xd3        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )

#define SHRLir(IM,RD,X)           (((IM)==1) ?    _O_Mrm          (X,0xd1   ,_b11,_b101,_r4(RD)                             ) : \
                                                  _O_Mrm_B        (X,0xc1   ,_b11,_b101,_r4(RD)                     ,_u1(IM) ) )
#define SHRLim(IM,MD,MB,MS,MI,X)  (((IM)==1) ?    _O_r_X          (X,0xd1        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  _O_r_X_B        (X,0xc1        ,_b101             ,MD,MB,MI,MS    ,_u1(IM) ) )
#define SHRLrr(RS,RD,X)           (((RS)==_CL) ?  _O_Mrm          (X,0xd3   ,_b11,_b101,_r4(RD)                             ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )
#define SHRLrm(RS,MD,MB,MS,MI,X)  (((RS)==_CL) ?  _O_r_X          (X,0xd3        ,_b101             ,MD,MB,MI,MS            ) : \
                                                  ASMFAIL         ("source register must be CL"                           ) )


#define STC(X)                            _O              (X,0xf9                                                           )


#define SUBBrr(RS, RD,X)                  _O_Mrm          (X,0x28           ,_b11,_r1(RS),_r1(RD)                           )
#define SUBBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x2a                ,_r1(RD)           ,MD,MB,MI,MS            )
#define SUBBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x28                ,_r1(RS)           ,MD,MB,MI,MS            )
#define SUBBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b101  ,_r1(RD)                   ,_s1(IM))
#define SUBBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b101             ,MD,MB,MI,MS    ,_s1(IM))
        
#define SUBWrr(RS, RD,X)                  _wO_Mrm         (X,0x29           ,_b11,_r2(RS),_r2(RD)                           )
#define SUBWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x2b                ,_r2(RD)           ,MD,MB,MI,MS            )
#define SUBWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x29                ,_r2(RS)           ,MD,MB,MI,MS            )
#define SUBWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b101  ,_r2(RD)                   ,_s2(IM))
#define SUBWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b101             ,MD,MB,MI,MS    ,_s2(IM))
        
#define SUBLrr(RS, RD,X)                  _O_Mrm          (X,0x29           ,_b11,_r4(RS),_r4(RD)                           )
#define SUBLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x2b                ,_r4(RD)           ,MD,MB,MI,MS            )
#define SUBLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x29                ,_r4(RS)           ,MD,MB,MI,MS            )
#define SUBLir(IM, RD,X)                  _Os_Mrm_sL      (X,0x81           ,_b11,_b101  ,_r4(RD)                   ,IM     )
#define SUBLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL      (X,0x81                ,_b101             ,MD,MB,MI,MS    ,IM     )


#define TESTBrr(RS, RD,X)                 _O_Mrm          (X,0x84           ,_b11,_r1(RS),_r1(RD)                           )
#define TESTBrm(RS, MD, MB, MI, MS,X)     _O_r_X          (X,0x84                ,_r1(RS)           ,MD,MB,MI,MS            )
#define TESTBir(IM, RD,X)                 _O_Mrm_B        (X,0xf6           ,_b11,_b000  ,_r1(RD)                   ,_u1(IM))
#define TESTBim(IM, MD, MB, MI, MS,X)     _O_r_X_B        (X,0xf6                ,_b000             ,MD,MB,MI,MS    ,_u1(IM))

#define TESTWrr(RS, RD,X)                 _wO_Mrm         (X,0x85           ,_b11,_r2(RS),_r2(RD)                           )
#define TESTWrm(RS, MD, MB, MI, MS,X)     _wO_r_X         (X,0x85                ,_r2(RS)           ,MD,MB,MI,MS            )
#define TESTWir(IM, RD,X)                 _wO_Mrm_W       (X,0xf7           ,_b11,_b000  ,_r2(RD)                   ,_u2(IM))
#define TESTWim(IM, MD, MB, MI, MS,X)     _wO_r_X_W       (X,0xf7                ,_b000             ,MD,MB,MI,MS    ,_u2(IM))

#define TESTLrr(RS, RD,X)                 _O_Mrm          (X,0x85           ,_b11,_r4(RS),_r4(RD)                           )
#define TESTLrm(RS, MD, MB, MI, MS,X)     _O_r_X          (X,0x85                ,_r4(RS)           ,MD,MB,MI,MS            )
#define TESTLir(IM, RD,X)                 _O_Mrm_L        (X,0xf7           ,_b11,_b000  ,_r4(RD)                   ,IM     )
#define TESTLim(IM, MD, MB, MI, MS,X)     _O_r_X_L        (X,0xf7                ,_b000             ,MD,MB,MI,MS    ,IM     )


#define XADDBrr(RS,RD,X)                  _OO_Mrm         (X,0x0fc0         ,_b11,_r1(RS),_r1(RD)                           )
#define XADDBrm(RS,MD,MB,MI,MS,X)         _OO_r_X         (X,0x0fc0              ,_r1(RS)           ,MD,MB,MI,MS            )

#define XADDWrr(RS,RD,X)                  _wOO_Mrm        (X,0x0fc1         ,_b11,_r2(RS),_r2(RD)                           )
#define XADDWrm(RS,MD,MB,MI,MS,X)         _wOO_r_X        (X,0x0fc1              ,_r2(RS)           ,MD,MB,MI,MS            )

#define XADDLrr(RS,RD,X)                  _OO_Mrm         (X,0x0fc1         ,_b11,_r4(RS),_r4(RD)                           )
#define XADDLrm(RS,MD,MB,MI,MS,X)         _OO_r_X         (X,0x0fc1              ,_r4(RS)           ,MD,MB,MI,MS            )


#define XCHGBrr(RS,RD,X)                  _O_Mrm          (X,0x86           ,_b11,_r1(RS),_r1(RD)                           )
#define XCHGBrm(RS,MD,MB,MI,MS,X)         _O_r_X          (X,0x86                ,_r1(RS)           ,MD,MB,MI,MS            )

#define XCHGWrr(RS,RD,X)                  _wO_Mrm         (X,0x87           ,_b11,_r2(RS),_r2(RD)                           )
#define XCHGWrm(RS,MD,MB,MI,MS,X)         _wO_r_X         (X,0x87                ,_r2(RS)           ,MD,MB,MI,MS            )

#define XCHGLrr(RS,RD,X)                  _O_Mrm          (X,0x87           ,_b11,_r4(RS),_r4(RD)                           )
#define XCHGLrm(RS,MD,MB,MI,MS,X)         _O_r_X          (X,0x87                ,_r4(RS)           ,MD,MB,MI,MS            )


#define XORBrr(RS, RD,X)                  _O_Mrm          (X,0x30           ,_b11,_r1(RS),_r1(RD)                           )
#define XORBmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x32                ,_r1(RD)           ,MD,MB,MI,MS            )
#define XORBrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x30                ,_r1(RS)           ,MD,MB,MI,MS            )
#define XORBir(IM, RD,X)                  _O_Mrm_B        (X,0x80           ,_b11,_b110  ,_r1(RD)                   ,_s1(IM))
#define XORBim(IM, MD, MB, MI, MS,X)      _O_r_X_B        (X,0x80                ,_b110             ,MD,MB,MI,MS    ,_s1(IM))

#define XORWrr(RS, RD,X)                  _wO_Mrm         (X,0x31           ,_b11,_r2(RS),_r2(RD)                           )
#define XORWmr(MD, MB, MI, MS, RD,X)      _wO_r_X         (X,0x33                ,_r2(RD)           ,MD,MB,MI,MS            )
#define XORWrm(RS, MD, MB, MI, MS,X)      _wO_r_X         (X,0x31                ,_r2(RS)           ,MD,MB,MI,MS            )
#define XORWir(IM, RD,X)                  _wOs_Mrm_sW     (X,0x81           ,_b11,_b110  ,_r2(RD)                   ,_s2(IM))
#define XORWim(IM, MD, MB, MI, MS,X)      _wOs_r_X_sW     (X,0x81                ,_b110             ,MD,MB,MI,MS    ,_s2(IM))

#define XORLrr(RS, RD,X)                  _O_Mrm          (X,0x31           ,_b11,_r4(RS),_r4(RD)                           )
#define XORLmr(MD, MB, MI, MS, RD,X)      _O_r_X          (X,0x33                ,_r4(RD)           ,MD,MB,MI,MS            )
#define XORLrm(RS, MD, MB, MI, MS,X)      _O_r_X          (X,0x31                ,_r4(RS)           ,MD,MB,MI,MS            )
#define XORLir(IM, RD,X)                  _Os_Mrm_sL      (X,0x81           ,_b11,_b110  ,_r4(RD)                   ,IM     )
#define XORLim(IM, MD, MB, MI, MS,X)      _Os_r_X_sL      (X,0x81                ,_b110             ,MD,MB,MI,MS    ,IM     )

#define SALBir  SHLBir  
#define SALBim  SHLBim  
#define SALBrr  SHLBrr  
#define SALBrm  SHLBrm  
#define SALWir  SHLWir  
#define SALWim  SHLWim  
#define SALWrr  SHLWrr  
#define SALWrm  SHLWrm  
#define SALLir  SHLLir  
#define SALLim  SHLLim  
#define SALLrr  SHLLrr  
#define SALLrm  SHLLrm  
