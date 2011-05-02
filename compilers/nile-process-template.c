typedef struct {

[[ (name type) in pvars
   `type` `name`;
]]

} `prefix`_`pname`_vars_t;

nile_Buffer_t *
`prefix`_`pname`_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    `prefix`_`pname`_vars_t *vars = nile_Process_vars (p);
    `prefix`_`pname`_vars_t v = *vars;
    `prologue`
    *vars = v;
    return out;
}

nile_Buffer_t *
`prefix`_`pname`_body (nile_Process_t *p, nile_Buffer_t *in, nile_Buffer_t *out)
{
    `prefix`_`pname`_vars_t *vars = nile_Process_vars (p);
    `prefix`_`pname`_vars_t v = *vars;
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        `prefix`_`pname`_vars_t v_ = v;

[[ (name type) in patvars
        `type` `name` = nile_Buffer_pop_head (in);
]]

        `body`
        v = v_;
    }
    *vars = v;
    return out;
}

nile_Buffer_t *
`prefix`_`pname`_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    `prefix`_`pname`_vars_t *vars = nile_Process_vars (p);
    `prefix`_`pname`_vars_t v = *vars;
    `epilogue`
    return out;
}

nile_Process_t *
`prefix`_`pname` (nile_Process_t *p

[[ (name type cname) in pargs
                  ,`type` `name`
]]

                 )
{
    p = nile_Process (p, `inquantum`, sizeof (`prefix`_`pname`_vars_t),
                      `prefix`_`pname`_prologue,
                      `prefix`_`pname`_body,
                      `prefix`_`pname`_epilogue);
    if (p) {
        `prefix`_`name`_vars_t *vars = nile_Process_vars (p);

[[ (name type cname) in pargs
        vars->`name` = cname;
]]

    }
    return p;
}
