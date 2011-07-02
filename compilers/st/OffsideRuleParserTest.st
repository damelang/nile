name        = "x" | "foo" | "bar" | "baz"
stmt :dummy =
    indent(nil)
    ( name:n eol -> [n]
    | ``if'' name:c eol indented(#stmts):t indent(nil) ``else'' eol indented(#stmts):e -> [{#if. c. t. e}]
    | ``if'' name:c eol indented(#stmts):t -> [{#if. c. t}]
    )
stmts       = stmt(nil)*
start       = stmts:ans (space | nl)* end -> [ans]
test
    ^ self matchAll: 'foo
if x
  foo
  bar
  if x
    baz
    baz
    foo
    if bar
      baz
else
  baz
' with: #start
