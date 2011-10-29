#ifndef TEXT_LAYOUT_H
#define TEXT_LAYOUT_H

#include "nile.h"

nile_Process_t *
text_layout_MakeWords (nile_Process_t *p);

nile_Process_t *
text_layout_PlaceWords (nile_Process_t *p, 
                        float v_o_x, 
                        float v_o_y, 
                        float v_w, 
                        float v_h);

nile_Process_t *
text_layout_DuplicatePlacement (nile_Process_t *p);

nile_Process_t *
text_layout_LayoutText (nile_Process_t *p, 
                        float v_o_x, 
                        float v_o_y, 
                        float v_w, 
                        float v_h);



#endif

