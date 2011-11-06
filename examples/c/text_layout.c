#define NILE_INCLUDE_PROCESS_API
#include "nile.h"
#include "text_layout.h"

#define IN_QUANTUM 2
#define OUT_QUANTUM 3

typedef struct {
    nile_Real_t v_w;
    nile_Real_t v_W_w;
    nile_Real_t v_W_s;
    nile_Real_t v_W_n;
} text_layout_MakeWords_vars_t;

static nile_Buffer_t *
text_layout_MakeWords_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_MakeWords_vars_t *vars = nile_Process_vars (p);
    text_layout_MakeWords_vars_t v = *vars;
    nile_Real_t t_7 = nile_Real (0);
    nile_Real_t t_8 = nile_Real (0);
    nile_Real_t t_9 = nile_Real (0);
    nile_Real_t t_6_1 = t_7;
    nile_Real_t t_6_2 = t_8;
    nile_Real_t t_6_3 = t_9;
    nile_Real_t t_10_w = t_6_1;
    nile_Real_t t_10_s = t_6_2;
    nile_Real_t t_10_n = t_6_3;
    v.v_W_w = t_10_w;
    v.v_W_s = t_10_s;
    v.v_W_n = t_10_n;
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_MakeWords_body (nile_Process_t *p,
                            nile_Buffer_t *in,
                            nile_Buffer_t *out)
{
    text_layout_MakeWords_vars_t *vars = nile_Process_vars (p);
    text_layout_MakeWords_vars_t v = *vars;
    
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        text_layout_MakeWords_vars_t v_ = v;
        nile_Real_t v_G_w = nile_Buffer_pop_head(in);
        nile_Real_t v_G_s = nile_Buffer_pop_head(in);
        nile_Real_t t_11 = nile_Real_neq(v_G_s, v.v_W_s);
        nile_Real_t t_12 = nile_Real (2);
        nile_Real_t t_13 = nile_Real_eq(v.v_W_s, t_12);
        nile_Real_t t_14 = nile_Real_or(t_11, t_13);
        nile_Real_t t_15 = nile_Real_add(v.v_W_w, v_G_w);
        nile_Real_t t_16 = nile_Real_gt(t_15, v.v_w);
        nile_Real_t t_17 = nile_Real_or(t_14, t_16);
        if (nile_Real_nz (t_17)) {
            nile_Real_t t_19 = nile_Real (1);
            nile_Real_t t_18_1 = v_G_w;
            nile_Real_t t_18_2 = v_G_s;
            nile_Real_t t_18_3 = t_19;
            nile_Real_t t_20_w = t_18_1;
            nile_Real_t t_20_s = t_18_2;
            nile_Real_t t_20_n = t_18_3;
            v_.v_W_w = t_20_w;
            v_.v_W_s = t_20_s;
            v_.v_W_n = t_20_n;
            if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                out = nile_Process_append_output (p, out);
            nile_Buffer_push_tail(out, v.v_W_w);
            nile_Buffer_push_tail(out, v.v_W_s);
            nile_Buffer_push_tail(out, v.v_W_n);
        }
        else {
            nile_Real_t t_22 = nile_Real_add(v.v_W_w, v_G_w);
            nile_Real_t t_23 = nile_Real (1);
            nile_Real_t t_24 = nile_Real_add(v.v_W_n, t_23);
            nile_Real_t t_21_1 = t_22;
            nile_Real_t t_21_2 = v.v_W_s;
            nile_Real_t t_21_3 = t_24;
            nile_Real_t t_25_w = t_21_1;
            nile_Real_t t_25_s = t_21_2;
            nile_Real_t t_25_n = t_21_3;
            v_.v_W_w = t_25_w;
            v_.v_W_s = t_25_s;
            v_.v_W_n = t_25_n;
        }
        v = v_;
    }
    
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_MakeWords_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_MakeWords_vars_t *vars = nile_Process_vars (p);
    text_layout_MakeWords_vars_t v = *vars;
    if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
        out = nile_Process_append_output (p, out);
    nile_Buffer_push_tail(out, v.v_W_w);
    nile_Buffer_push_tail(out, v.v_W_s);
    nile_Buffer_push_tail(out, v.v_W_n);
    return out;
}

nile_Process_t *
text_layout_MakeWords (nile_Process_t *p, 
                       float v_w)
{
    text_layout_MakeWords_vars_t *vars;
    text_layout_MakeWords_vars_t v;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_MakeWords_prologue, text_layout_MakeWords_body, text_layout_MakeWords_epilogue);
    if (p) {
        vars = nile_Process_vars (p);
        v.v_w = nile_Real (v_w);
        *vars = v;
    }
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

#define IN_QUANTUM 3
#define OUT_QUANTUM 3

typedef struct {
    nile_Real_t v_w;
    nile_Real_t v_o;
} text_layout_InsertLineBreaks_vars_t;

static nile_Buffer_t *
text_layout_InsertLineBreaks_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_InsertLineBreaks_vars_t *vars = nile_Process_vars (p);
    text_layout_InsertLineBreaks_vars_t v = *vars;
    nile_Real_t t_2 = nile_Real (0);
    v.v_o = t_2;
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_InsertLineBreaks_body (nile_Process_t *p,
                                   nile_Buffer_t *in,
                                   nile_Buffer_t *out)
{
    text_layout_InsertLineBreaks_vars_t *vars = nile_Process_vars (p);
    text_layout_InsertLineBreaks_vars_t v = *vars;
    
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        text_layout_InsertLineBreaks_vars_t v_ = v;
        nile_Real_t v_W_w = nile_Buffer_pop_head(in);
        nile_Real_t v_W_s = nile_Buffer_pop_head(in);
        nile_Real_t v_W_n = nile_Buffer_pop_head(in);
        nile_Real_t t_3 = nile_Real (2);
        nile_Real_t t_4 = nile_Real_eq(v_W_s, t_3);
        if (nile_Real_nz (t_4)) {
            nile_Real_t t_5 = nile_Real (0);
            v_.v_o = t_5;
            if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                out = nile_Process_append_output (p, out);
            nile_Buffer_push_tail(out, v_W_w);
            nile_Buffer_push_tail(out, v_W_s);
            nile_Buffer_push_tail(out, v_W_n);
        }
        else {
            nile_Real_t t_6 = nile_Real (1);
            nile_Real_t t_7 = nile_Real_eq(v_W_s, t_6);
            nile_Real_t t_8 = nile_Real_add(v.v_o, v_W_w);
            nile_Real_t t_9 = nile_Real_leq(t_8, v.v_w);
            nile_Real_t t_10 = nile_Real_or(t_7, t_9);
            if (nile_Real_nz (t_10)) {
                nile_Real_t t_11 = nile_Real_add(v.v_o, v_W_w);
                v_.v_o = t_11;
                if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                    out = nile_Process_append_output (p, out);
                nile_Buffer_push_tail(out, v_W_w);
                nile_Buffer_push_tail(out, v_W_s);
                nile_Buffer_push_tail(out, v_W_n);
            }
            else {
                nile_Real_t t_12 = nile_Real (0);
                nile_Real_t t_13 = nile_Real_add(t_12, v_W_w);
                v_.v_o = t_13;
                nile_Real_t t_15 = nile_Real (0);
                nile_Real_t t_16 = nile_Real (2);
                nile_Real_t t_17 = nile_Real (0);
                nile_Real_t t_14_1 = t_15;
                nile_Real_t t_14_2 = t_16;
                nile_Real_t t_14_3 = t_17;
                nile_Real_t t_18_w = t_14_1;
                nile_Real_t t_18_s = t_14_2;
                nile_Real_t t_18_n = t_14_3;
                if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                    out = nile_Process_append_output (p, out);
                nile_Buffer_push_tail(out, t_18_w);
                nile_Buffer_push_tail(out, t_18_s);
                nile_Buffer_push_tail(out, t_18_n);
                if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                    out = nile_Process_append_output (p, out);
                nile_Buffer_push_tail(out, v_W_w);
                nile_Buffer_push_tail(out, v_W_s);
                nile_Buffer_push_tail(out, v_W_n);
            }
        }
        v = v_;
    }
    
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_InsertLineBreaks_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_InsertLineBreaks_vars_t *vars = nile_Process_vars (p);
    text_layout_InsertLineBreaks_vars_t v = *vars;
    return out;
}

nile_Process_t *
text_layout_InsertLineBreaks (nile_Process_t *p, 
                              float v_w)
{
    text_layout_InsertLineBreaks_vars_t *vars;
    text_layout_InsertLineBreaks_vars_t v;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_InsertLineBreaks_prologue, text_layout_InsertLineBreaks_body, text_layout_InsertLineBreaks_epilogue);
    if (p) {
        vars = nile_Process_vars (p);
        v.v_w = nile_Real (v_w);
        *vars = v;
    }
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

#define IN_QUANTUM 3
#define OUT_QUANTUM 5

typedef struct {
    nile_Real_t v_o_x;
    nile_Real_t v_o_y;
    nile_Real_t v_h;
    nile_Real_t v_x;
    nile_Real_t v_y;
} text_layout_PlaceWords_vars_t;

static nile_Buffer_t *
text_layout_PlaceWords_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_PlaceWords_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceWords_vars_t v = *vars;
    v.v_x = v.v_o_x;
    v.v_y = v.v_o_y;
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_PlaceWords_body (nile_Process_t *p,
                             nile_Buffer_t *in,
                             nile_Buffer_t *out)
{
    text_layout_PlaceWords_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceWords_vars_t v = *vars;
    
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        text_layout_PlaceWords_vars_t v_ = v;
        nile_Real_t v_W_w = nile_Buffer_pop_head(in);
        nile_Real_t v_W_s = nile_Buffer_pop_head(in);
        nile_Real_t v_W_n = nile_Buffer_pop_head(in);
        nile_Real_t t_2_1 = v.v_x;
        nile_Real_t t_2_2 = v.v_y;
        nile_Real_t t_1_1_w = v_W_w;
        nile_Real_t t_1_1_s = v_W_s;
        nile_Real_t t_1_1_n = v_W_n;
        nile_Real_t t_1_2_1 = t_2_1;
        nile_Real_t t_1_2_2 = t_2_2;
        nile_Real_t t_3_1_w = t_1_1_w;
        nile_Real_t t_3_1_s = t_1_1_s;
        nile_Real_t t_3_1_n = t_1_1_n;
        nile_Real_t t_3_2_x = t_1_2_1;
        nile_Real_t t_3_2_y = t_1_2_2;
        if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
            out = nile_Process_append_output (p, out);
        nile_Buffer_push_tail(out, t_3_1_w);
        nile_Buffer_push_tail(out, t_3_1_s);
        nile_Buffer_push_tail(out, t_3_1_n);
        nile_Buffer_push_tail(out, t_3_2_x);
        nile_Buffer_push_tail(out, t_3_2_y);
        nile_Real_t t_4 = nile_Real (2);
        nile_Real_t t_5 = nile_Real_eq(v_W_s, t_4);
        nile_Real_t t_6 = nile_Real_add(v.v_x, v_W_w);
        nile_Real_t t_7 = nile_Real_nz (t_5) ? v.v_o_x : t_6;
        v_.v_x = t_7;
        nile_Real_t t_8 = nile_Real (2);
        nile_Real_t t_9 = nile_Real_eq(v_W_s, t_8);
        nile_Real_t t_10 = nile_Real_add(v.v_y, v.v_h);
        nile_Real_t t_11 = nile_Real_nz (t_9) ? t_10 : v.v_y;
        v_.v_y = t_11;
        v = v_;
    }
    
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_PlaceWords_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_PlaceWords_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceWords_vars_t v = *vars;
    return out;
}

nile_Process_t *
text_layout_PlaceWords (nile_Process_t *p, 
                        float v_o_x, 
                        float v_o_y, 
                        float v_h)
{
    text_layout_PlaceWords_vars_t *vars;
    text_layout_PlaceWords_vars_t v;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_PlaceWords_prologue, text_layout_PlaceWords_body, text_layout_PlaceWords_epilogue);
    if (p) {
        vars = nile_Process_vars (p);
        v.v_o_x = nile_Real (v_o_x);
        v.v_o_y = nile_Real (v_o_y);
        v.v_h = nile_Real (v_h);
        *vars = v;
    }
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

#define IN_QUANTUM 5
#define OUT_QUANTUM 2

typedef struct {
} text_layout_DuplicatePlacement_vars_t;

static nile_Buffer_t *
text_layout_DuplicatePlacement_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_DuplicatePlacement_vars_t *vars = nile_Process_vars (p);
    text_layout_DuplicatePlacement_vars_t v = *vars;
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_DuplicatePlacement_body (nile_Process_t *p,
                                     nile_Buffer_t *in,
                                     nile_Buffer_t *out)
{
    text_layout_DuplicatePlacement_vars_t *vars = nile_Process_vars (p);
    text_layout_DuplicatePlacement_vars_t v = *vars;
    
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        text_layout_DuplicatePlacement_vars_t v_ = v;
        nile_Real_t v_W_w = nile_Buffer_pop_head(in);
        nile_Real_t v_W_s = nile_Buffer_pop_head(in);
        nile_Real_t v_W_n = nile_Buffer_pop_head(in);
        nile_Real_t v_P_x = nile_Buffer_pop_head(in);
        nile_Real_t v_P_y = nile_Buffer_pop_head(in);
        nile_Real_t t_1 = nile_Real (0);
        nile_Real_t t_2 = nile_Real_gt(v_W_n, t_1);
        if (nile_Real_nz (t_2)) {
            if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                out = nile_Process_append_output (p, out);
            nile_Buffer_push_tail(out, v_P_x);
            nile_Buffer_push_tail(out, v_P_y);
            nile_Real_t t_5 = nile_Real (1);
            nile_Real_t t_6 = nile_Real_sub(v_W_n, t_5);
            nile_Real_t t_4_1 = v_W_w;
            nile_Real_t t_4_2 = v_W_s;
            nile_Real_t t_4_3 = t_6;
            nile_Real_t t_3_1_1 = t_4_1;
            nile_Real_t t_3_1_2 = t_4_2;
            nile_Real_t t_3_1_3 = t_4_3;
            nile_Real_t t_3_2_x = v_P_x;
            nile_Real_t t_3_2_y = v_P_y;
            nile_Real_t t_7_1_w = t_3_1_1;
            nile_Real_t t_7_1_s = t_3_1_2;
            nile_Real_t t_7_1_n = t_3_1_3;
            nile_Real_t t_7_2_x = t_3_2_x;
            nile_Real_t t_7_2_y = t_3_2_y;
            if (nile_Buffer_headroom (in) < IN_QUANTUM)
                in = nile_Process_prefix_input (p, in);
            nile_Buffer_push_head(in, t_7_2_y);
            nile_Buffer_push_head(in, t_7_2_x);
            nile_Buffer_push_head(in, t_7_1_n);
            nile_Buffer_push_head(in, t_7_1_s);
            nile_Buffer_push_head(in, t_7_1_w);
        }
        else {
            ; /* no-op */
        }
        v = v_;
    }
    
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_DuplicatePlacement_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_DuplicatePlacement_vars_t *vars = nile_Process_vars (p);
    text_layout_DuplicatePlacement_vars_t v = *vars;
    return out;
}

nile_Process_t *
text_layout_DuplicatePlacement (nile_Process_t *p)
{
    text_layout_DuplicatePlacement_vars_t *vars;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_DuplicatePlacement_prologue, text_layout_DuplicatePlacement_body, text_layout_DuplicatePlacement_epilogue);
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

#define IN_QUANTUM 4
#define OUT_QUANTUM 2

typedef struct {
    nile_Real_t v_x;
    nile_Real_t v_y;
    nile_Real_t v_o;
} text_layout_PlaceGlyphs_vars_t;

static nile_Buffer_t *
text_layout_PlaceGlyphs_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_PlaceGlyphs_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceGlyphs_vars_t v = *vars;
    nile_Real_t t_4 = nile_Real (0);
    v.v_x = t_4;
    nile_Real_t t_5 = nile_Real (0);
    v.v_y = t_5;
    nile_Real_t t_6 = nile_Real (0);
    v.v_o = t_6;
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_PlaceGlyphs_body (nile_Process_t *p,
                              nile_Buffer_t *in,
                              nile_Buffer_t *out)
{
    text_layout_PlaceGlyphs_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceGlyphs_vars_t v = *vars;
    
    while (!nile_Buffer_is_empty (in) && !nile_Buffer_quota_hit (out)) {
        text_layout_PlaceGlyphs_vars_t v_ = v;
        nile_Real_t t_7;
        v_.v_x = nile_Buffer_pop_head(in);
        v_.v_y = nile_Buffer_pop_head(in);
        nile_Real_t v_w = nile_Buffer_pop_head(in);
        t_7 = nile_Buffer_pop_head(in);
        nile_Real_t t_8 = nile_Real_eq(v.v_x, v_.v_x);
        nile_Real_t t_9 = nile_Real_eq(v.v_y, v_.v_y);
        nile_Real_t t_10 = nile_Real_and(t_8, t_9);
        if (nile_Real_nz (t_10)) {
            nile_Real_t t_11 = nile_Real_add(v.v_o, v_w);
            v_.v_o = t_11;
            nile_Real_t t_13 = nile_Real_add(v_.v_x, v.v_o);
            nile_Real_t t_12_1 = t_13;
            nile_Real_t t_12_2 = v_.v_y;
            nile_Real_t t_14_x = t_12_1;
            nile_Real_t t_14_y = t_12_2;
            if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                out = nile_Process_append_output (p, out);
            nile_Buffer_push_tail(out, t_14_x);
            nile_Buffer_push_tail(out, t_14_y);
        }
        else {
            nile_Real_t t_15 = nile_Real (0);
            nile_Real_t t_16 = nile_Real_add(t_15, v_w);
            v_.v_o = t_16;
            nile_Real_t t_18 = nile_Real (0);
            nile_Real_t t_19 = nile_Real_add(v_.v_x, t_18);
            nile_Real_t t_17_1 = t_19;
            nile_Real_t t_17_2 = v_.v_y;
            nile_Real_t t_20_x = t_17_1;
            nile_Real_t t_20_y = t_17_2;
            if (nile_Buffer_tailroom (out) < OUT_QUANTUM)
                out = nile_Process_append_output (p, out);
            nile_Buffer_push_tail(out, t_20_x);
            nile_Buffer_push_tail(out, t_20_y);
        }
        v = v_;
    }
    
    *vars = v;
    return out;
}

static nile_Buffer_t *
text_layout_PlaceGlyphs_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_PlaceGlyphs_vars_t *vars = nile_Process_vars (p);
    text_layout_PlaceGlyphs_vars_t v = *vars;
    return out;
}

nile_Process_t *
text_layout_PlaceGlyphs (nile_Process_t *p)
{
    text_layout_PlaceGlyphs_vars_t *vars;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_PlaceGlyphs_prologue, text_layout_PlaceGlyphs_body, text_layout_PlaceGlyphs_epilogue);
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

#define IN_QUANTUM 2
#define OUT_QUANTUM 2

typedef struct {
    nile_Real_t v_o_x;
    nile_Real_t v_o_y;
    nile_Real_t v_w;
    nile_Real_t v_h;
} text_layout_LayoutText_vars_t;

static nile_Buffer_t *
text_layout_LayoutText_prologue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_LayoutText_vars_t *vars = nile_Process_vars (p);
    text_layout_LayoutText_vars_t v = *vars;
    ; /* no-op */
    nile_Process_t *t_1 = text_layout_MakeWords(p, nile_Real_tof (v.v_w));
    nile_Process_t *t_2 = text_layout_InsertLineBreaks(p, nile_Real_tof (v.v_w));
    nile_Process_t *t_3 = text_layout_PlaceWords(p, nile_Real_tof (v.v_o_x), nile_Real_tof (v.v_o_y), nile_Real_tof (v.v_h));
    nile_Process_t *t_4 = nile_Process_pipe (t_3, text_layout_DuplicatePlacement(p), NILE_NULL);
    nile_Process_t *t_5 = nile_Process_pipe (t_2, t_4, NILE_NULL);
    nile_Process_t *t_6 = nile_Process_pipe (t_1, t_5, NILE_NULL);
    nile_Real_t t_7 = nile_Real (2);
    nile_Process_t *t_8 = nile_Process_pipe (NILE_NULL);
    nile_Real_t t_9 = nile_Real (2);
    nile_Process_t *t_10 = nile_DupZip(p, 2, t_6, nile_Real_toi (t_7), t_8, nile_Real_toi (t_9));
    nile_Process_t *t_11 = nile_Process_pipe (t_10, text_layout_PlaceGlyphs(p), NILE_NULL);
    return nile_Process_swap (p, t_11, out);
    *vars = v;
    return out;
}

#define text_layout_LayoutText_body 0

static nile_Buffer_t *
text_layout_LayoutText_epilogue (nile_Process_t *p, nile_Buffer_t *out)
{
    text_layout_LayoutText_vars_t *vars = nile_Process_vars (p);
    text_layout_LayoutText_vars_t v = *vars;
    ; /* no-op */
    return out;
}

nile_Process_t *
text_layout_LayoutText (nile_Process_t *p, 
                        float v_o_x, 
                        float v_o_y, 
                        float v_w, 
                        float v_h)
{
    text_layout_LayoutText_vars_t *vars;
    text_layout_LayoutText_vars_t v;
    p = nile_Process (p, IN_QUANTUM, sizeof (*vars), text_layout_LayoutText_prologue, text_layout_LayoutText_body, text_layout_LayoutText_epilogue);
    if (p) {
        vars = nile_Process_vars (p);
        v.v_o_x = nile_Real (v_o_x);
        v.v_o_y = nile_Real (v_o_y);
        v.v_w = nile_Real (v_w);
        v.v_h = nile_Real (v_h);
        *vars = v;
    }
    return p;
}

#undef IN_QUANTUM
#undef OUT_QUANTUM

