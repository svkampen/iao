#importonce

#import "zeropage.inc"
#import "val_to_dec_char.asm"
#import "scrn_addr.inc"
#import "pseudo.lib"

update_itb:
        jsr recalc_itb
        jsr write_itb
        rts

recalc_itb:
        rts

write_itb:
        
        rts
